local NO_PERMISSION = {
    es = 'No tienes permiso para usar el editor de escenas',
    en = 'You do not have permission to use the scene editor',
}

RegisterCommand(Config.Command, function(src)
    if src == 0 then
        print('[dwkambience] el editor solo se puede abrir in-game')
        return
    end

    if not Permissions.canEdit(src) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = NO_PERMISSION[Config.Locale] or NO_PERMISSION.en })
        return
    end

    Log.action(src, 'Editor abierto')
    TriggerClientEvent('dwkambience:openEditor', src)
end, false)

-- El cliente avisa al cerrar el editor para liberar su bloqueo
RegisterNetEvent('dwkambience:editorClosed', function()
    Locks.releaseAll(source)
end)
