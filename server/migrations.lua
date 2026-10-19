-- Migraciones SQL automáticas: al arrancar aplica, en orden, las de sql/ que aún no estén registradas.
-- Cada una se ejecuta una sola vez; la tabla dwkambience_migrations guarda las ya aplicadas.
Migrations = { ready = false, failed = false }

-- Para añadir una migración: crea sql/NNN_nombre.sql y añádela al final de esta lista. No reordenar ni renombrar.
local FILES = {
    '001_init.sql',
}

local RESOURCE = GetCurrentResourceName()

--- Divide un fichero SQL en sentencias. Ignora líneas de comentario `--`.
--- No soporta `;` dentro de cadenas: las migraciones son solo DDL.
local function statements(sql)
    local lines = {}
    for line in sql:gmatch('[^\n]+') do
        if not line:match('^%s*%-%-') then lines[#lines + 1] = line end
    end
    local out = {}
    for stmt in table.concat(lines, '\n'):gmatch('[^;]+') do
        stmt = stmt:match('^%s*(.-)%s*$')
        if stmt ~= '' then out[#out + 1] = stmt end
    end
    return out
end

local function run()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dwkambience_migrations` (
          `id` VARCHAR(64) NOT NULL,
          `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    local applied = {}
    for _, row in ipairs(MySQL.query.await('SELECT id FROM dwkambience_migrations') or {}) do
        applied[row.id] = true
    end

    for _, file in ipairs(FILES) do
        if not applied[file] then
            local sql = LoadResourceFile(RESOURCE, 'sql/' .. file)
            if not sql then error(('no se encuentra sql/%s'):format(file)) end

            for _, stmt in ipairs(statements(sql)) do
                MySQL.query.await(stmt)
            end
            MySQL.insert.await('INSERT INTO dwkambience_migrations (id) VALUES (?)', { file })
            print(('[dwkambience] migración aplicada: %s'):format(file))
        end
    end
end

MySQL.ready(function()
    local ok, err = pcall(run)
    if ok then
        Migrations.ready = true
    else
        Migrations.failed = true
        print(('^1[dwkambience] error aplicando migraciones: %s^0'):format(err))
    end
end)
