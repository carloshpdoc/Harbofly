import Foundation

/// Integração com o Docker/OrbStack.
///
/// Docker não encaixa no modelo "acha pasta grande e joga na Lixeira": os dados
/// vivem num disk image único e *sparse* (o `.raw` reporta centenas de GB de
/// tamanho lógico, mas só alguns GB reais em disco). Apagar o arquivo mataria
/// TUDO de uma vez, e o espaço recuperável de verdade só sai via engine
/// (`docker system prune`), nunca por `rm` de pasta.
///
/// Por isso a medição aqui é o `Reclaimable` reportado pelo próprio engine, e a
/// ação é um prune conservador (containers parados, redes soltas, imagens
/// dangling e build cache) — sem `-a`/`--volumes`, que removeriam imagens
/// nomeadas e volumes ainda referenciáveis. Prune é irreversível: não passa pela
/// Lixeira.
enum DockerEngine {

    enum Status {
        /// Sem CLI do Docker na máquina.
        case absent
        /// Engine no ar. `reclaimable` = soma do que `docker system df` libera.
        case running(reclaimable: Int64, image: URL?)
        /// CLI presente mas daemon desligado. `imageBytes` = tamanho real
        /// (alocado) do disk image, mostrado só pra ciência.
        case stopped(imageBytes: Int64, image: URL?)
    }

    // MARK: descoberta

    /// GUI apps herdam um PATH mínimo, então sondamos os caminhos conhecidos do
    /// binário `docker` (que resolve o context ativo sozinho: Docker Desktop ou
    /// OrbStack).
    static func binary() -> URL? {
        let home = NSHomeDirectory()
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "\(home)/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "\(home)/.orbstack/bin/docker",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// Localiza o disk image do engine pra exibir/medir. Quando `context` é
    /// informado, prioriza o image do engine correspondente (evita mostrar o
    /// `.raw` do Docker Desktop enquanto o context ativo é o OrbStack, ou
    /// vice-versa).
    static func imagePath(context: String? = nil) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        func dockerDesktop() -> URL? {
            for rel in ["Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                        "Library/Containers/com.docker.docker/Data/vms/0/Docker.raw"] {
                let u = home.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
            return nil
        }
        func orbstack() -> URL? {
            // O id do Group Container inclui o Team ID, então varremos por nome.
            let gc = home.appendingPathComponent("Library/Group Containers")
            if let items = try? FileManager.default.contentsOfDirectory(atPath: gc.path) {
                for name in items where name.lowercased().contains("orbstack") {
                    let u = gc.appendingPathComponent("\(name)/data/data.img.raw")
                    if FileManager.default.fileExists(atPath: u.path) { return u }
                }
            }
            return nil
        }

        if let c = context?.lowercased(), c.contains("orbstack") {
            return orbstack() ?? dockerDesktop()
        }
        return dockerDesktop() ?? orbstack()
    }

    /// Nome do context ativo do docker (ex.: "orbstack", "desktop-linux").
    private static func currentContext(_ bin: URL) -> String? {
        let (out, ok) = run(bin, ["context", "show"], timeout: 8)
        let name = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (ok && !name.isEmpty) ? name : nil
    }

    // MARK: leitura

    static func probe() -> Status {
        guard let bin = binary() else { return .absent }
        let (out, ok) = run(bin, ["system", "df", "--format", "{{json .}}"], timeout: 15)
        if ok, !out.isEmpty {
            var total: Int64 = 0
            for line in out.split(separator: "\n") {
                guard let d = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let rec = obj["Reclaimable"] as? String else { continue }
                total += parseHumanBytes(rec)
            }
            return .running(reclaimable: total, image: imagePath(context: currentContext(bin)))
        }
        // daemon desligado: mede o disk image, se existir.
        if let img = imagePath(context: currentContext(bin)) {
            return .stopped(imageBytes: allocatedSize(img), image: img)
        }
        return .absent
    }

    // MARK: ação

    /// Prune conservador. Retorna true se pelo menos um comando teve sucesso.
    static func prune() -> Bool {
        guard let bin = binary() else { return false }
        let system = run(bin, ["system", "prune", "-f"], timeout: 180)
        let builder = run(bin, ["builder", "prune", "-f"], timeout: 180)
        return system.ok || builder.ok
    }

    // MARK: helpers

    /// Converte o tamanho humano do docker ("5.997GB (29%)", "961.1MB", "512B")
    /// em bytes. Unidades decimais (go-units): 1kB = 1000.
    static func parseHumanBytes(_ raw: String) -> Int64 {
        var str = raw
        if let r = str.range(of: " (") { str = String(str[..<r.lowerBound]) }
        str = str.trimmingCharacters(in: .whitespaces)
        // Mais longas primeiro: todas terminam em "B".
        let units: [(String, Double)] = [
            ("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1),
        ]
        for (u, mult) in units where str.hasSuffix(u) {
            let num = str.dropLast(u.count).trimmingCharacters(in: .whitespaces)
            return Int64((Double(num) ?? 0) * mult)
        }
        return Int64(Double(str) ?? 0)
    }

    private static func allocatedSize(_ url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
    }

    /// Roda um comando com timeout (watchdog mata o processo se travar, evitando
    /// pendurar o scan quando o daemon está subindo).
    private static func run(_ bin: URL, _ args: [String], timeout: TimeInterval) -> (out: String, ok: Bool) {
        let p = Process()
        p.executableURL = bin
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        // Garante um PATH sensato pro wrapper do docker achar seus helpers de context.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env

        do { try p.run() } catch { return ("", false) }

        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog.cancel()

        let s = String(data: data, encoding: .utf8) ?? ""
        return (s, p.terminationStatus == 0)
    }
}
