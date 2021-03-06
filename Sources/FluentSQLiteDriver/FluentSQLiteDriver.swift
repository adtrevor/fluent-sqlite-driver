extension DatabaseDriverFactory {
    public static func sqlite(
        file: String,
        maxConnectionsPerEventLoop: Int = 1
    ) -> DatabaseDriverFactory {
        .sqlite(
            configuration: .init(file: file),
            maxConnectionsPerEventLoop: maxConnectionsPerEventLoop
        )
    }
    
    public static func sqlite(
        configuration: SQLiteConfiguration = .init(storage: .memory),
        maxConnectionsPerEventLoop: Int = 1
    ) -> DatabaseDriverFactory {
        return DatabaseDriverFactory { databases in
            let db = SQLiteConnectionSource(
                configuration: configuration,
                threadPool: databases.threadPool
            )
            let pool = EventLoopGroupConnectionPool(
                source: db,
                maxConnectionsPerEventLoop: maxConnectionsPerEventLoop,
                on: databases.eventLoopGroup
            )
            return _FluentSQLiteDriver(pool: pool)
        }
    }
}

struct _ConnectionPoolSQLiteDatabase {
    let pool: EventLoopConnectionPool<SQLiteConnectionSource>
    let logger: Logger
}

extension _ConnectionPoolSQLiteDatabase: SQLiteDatabase {
    var eventLoop: EventLoop {
        self.pool.eventLoop
    }
    
    func lastAutoincrementID() -> EventLoopFuture<Int> {
        self.pool.withConnection(logger: self.logger) {
            $0.lastAutoincrementID()
        }
    }
    
    func withConnection<T>(_ closure: @escaping (SQLiteConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        self.pool.withConnection {
            closure($0)
        }
    }
    
    func query(_ query: String, _ binds: [SQLiteData], logger: Logger, _ onRow: @escaping (SQLiteRow) -> Void) -> EventLoopFuture<Void> {
        self.withConnection {
            $0.query(query, binds, logger: logger, onRow)
        }
    }
}

struct _FluentSQLiteDriver: DatabaseDriver {
    let pool: EventLoopGroupConnectionPool<SQLiteConnectionSource>
    
    var eventLoopGroup: EventLoopGroup {
        self.pool.eventLoopGroup
    }
    
    func makeDatabase(with context: DatabaseContext) -> Database {
        _FluentSQLiteDatabase(
            database: _ConnectionPoolSQLiteDatabase(pool: self.pool.pool(for: context.eventLoop), logger: context.logger),
            context: context
        )
    }
    
    func shutdown() {
        self.pool.shutdown()
    }
}
