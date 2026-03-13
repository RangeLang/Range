import NeatWeb
import Vapor

public enum NeatVaporBootstrap {
    public static func run<T: App>(_ appType: T.Type) async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        // app.logger.logLevel = .debug
        do {
            try await configure(app, for: T.self)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
