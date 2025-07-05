---@diagnostic disable: duplicate-set-field

-- =============================================
-- MARK: Variables
-- =============================================

Callbacks = {}

Callbacks.requests = {}
Callbacks.storage = {}
Callbacks.id = 0

local usingOxLib = lib and lib.callback ~= nil

-- =============================================
-- MARK: Internal Functions
-- =============================================

function Callbacks:Trigger(event, cb, invoker, ...)

    self.requests[self.id] = {
        await = type(cb) == "boolean",
        cb = cb or promise:new()
    }
    local table = self.requests[self.id]

    TriggerServerEvent("esx:triggerServerCallback", event, self.id, invoker, ...)

    self.id += 1

    return table.cb
end

function Callbacks:Execute(cb, id, ...)
    local success, errorString = pcall(cb, ...)

    if not success then
        print(("[^1ERROR^7] Failed to execute Callback with RequestId: ^5%s^7"):format(id))
        error(errorString)
        return
    end
end

function Callbacks:ServerRecieve(requestId, invoker, ...)
    if not self.requests[requestId] then
        return error(("Server Callback with requestId ^5%s^1 Was Called by ^5%s^1 but does not exist."):format(requestId, invoker))
    end

    local callback = self.requests[requestId]

    self.requests[requestId] = nil

    if callback.await then
        callback.cb:resolve({...})
    else
        self:Execute(callback.cb, requestId, ...)
    end
end

function Callbacks:Register(name, resource, cb)
    self.storage[name] = {
        resource = resource,
        cb = cb
    }
end

function Callbacks:ClientRecieve(eventName, requestId, invoker, ...)

    if not self.storage[eventName] then
        return error(("Client Callback with requestId ^5%s^1 Was Called by ^5%s^1 but does not exist."):format(eventName, invoker))
    end

    local returnCb = function(...)
        TriggerServerEvent("esx:clientCallback", requestId, invoker, ...)
    end
    local callback = self.storage[eventName].cb

    self:Execute(callback, requestId, returnCb, ...)
end

-- =============================================
-- MARK: ESX Functions
-- =============================================

---@param eventName string
---@param callback function
---@param ... any
---@return nil
function ESX.TriggerServerCallback(eventName, callback, ...)
    local invokingResource = GetInvokingResource()
    local invoker = (invokingResource and invokingResource ~= "unknown") and invokingResource or "es_extended"
    if usingOxLib then
        lib.callback(eventName, function(...)
            if callback then callback(...) end
        end, ...)
    else
        Callbacks:Trigger(eventName, callback, invoker, ...)
    end
end

---@param eventName string
---@param ... any
---@return any
function ESX.AwaitServerCallback(eventName, ...)
    local invokingResource = GetInvokingResource()
    local invoker = (invokingResource and invokingResource ~= "unknown") and invokingResource or "es_extended"
    if usingOxLib then
        return lib.callback.await(eventName, ...)
    else
        local p = Callbacks:Trigger(eventName, false, invoker, ...)
        if not p then return end

        SetTimeout(15000, function()
            if p.state == "pending" then
                p:reject("Server Callback Timed Out")
            end
        end)

        Citizen.Await(p)

        return table.unpack(p.value)
    end
end

function ESX.RegisterClientCallback(eventName, callback)
    local invokingResource = GetInvokingResource()
    local invoker = (invokingResource and invokingResource ~= "Unknown") and invokingResource or "es_extended"
    if usingOxLib then
        Callbacks.storage[eventName] = { resource = invoker, cb = callback }
        lib.callback.register(eventName, callback)
    else
        Callbacks:Register(eventName, invoker, callback)
    end
end

---@param eventName string
---@return boolean
function ESX.DoesClientCallbackExist(eventName)
    return Callbacks.storage[eventName] ~= nil
end

-- =============================================
-- MARK: Events
-- =============================================

if not usingOxLib then
    ESX.SecureNetEvent("esx:triggerClientCallback", function(...)
        Callbacks:ClientRecieve(...)
    end)

    ESX.SecureNetEvent("esx:serverCallback", function(...)
        Callbacks:ServerRecieve(...)
    end)
end

AddEventHandler("onResourceStop", function(resource)
    for k, v in pairs(Callbacks.storage) do
        if v.resource == resource then
            Callbacks.storage[k] = nil
        end
    end
end)
