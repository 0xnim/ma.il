local API = "http://135.181.126.38:8080"

-- persist login/session
local LS_TOKEN = "gurtmail.token"
local LS_USER  = "gurtmail.user"
local LS_UNAME = "gurtmail.uname"

local token = gurt.crumbs.get(LS_TOKEN) or ""
local userId = gurt.crumbs.get(LS_USER) or ""
local uname  = gurt.crumbs.get(LS_UNAME) or ""

-- elements
local username     = gurt.select("#username")
local password     = gurt.select("#password")
local authState    = gurt.select("#authState")
local fqdnInput    = gurt.select("#fqdn")
local domCount     = gurt.select("#domCount")
local domainsEl    = gurt.select("#domains")
local addrCount    = gurt.select("#addrCount")
local addressesEl  = gurt.select("#addresses")
local fromAddr     = gurt.select("#fromAddr")
local toInput      = gurt.select("#to")
local subjectInput = gurt.select("#subject")
local bodyInput    = gurt.select("#body")
local inboxEl      = gurt.select("#inbox")
local outboxEl     = gurt.select("#outbox")

-- helpers
local function clearChildren(el)
    while el.firstChild do
        el.firstChild:remove()
    end
end

local function setAuthState()
    if token ~= "" then
        authState.text = "Signed in as "..(uname or username.value or "user").." (id="..userId..")"
    else
        authState.text = "Not signed in."
    end
end

local function api(path, opts)
    opts = opts or {}
    opts.headers = opts.headers or {}
    if token ~= "" then
        opts.headers["authorization"] = "Bearer "..token
    end
    if opts.body and not opts.headers["content-type"] then
        opts.headers["content-type"] = "application/json"
    end
    local res = fetch(API..path, opts)
    if res:ok() then
        return res:json()
    else
        trace.error("API "..path.." failed: "..res.status)
        return {}
    end
end

-- refreshers
local function refreshDomains()
    local list = api("/api/domains")
    clearChildren(domainsEl)
    domCount.text = tostring(#list)

    for _, d in ipairs(list) do
        local wrap = gurt.create("div", { class="card" })

        local pillClass = "pill err"
        if d.status == "Verified" then pillClass = "pill ok"
        elseif d.status == "Pending" then pillClass = "pill warn" end

        local head = gurt.create("div", { style = "flex items-center gap-2" })
        head:append(gurt.create("h3", { text = d.fqdn, style="text-lg font-bold" }))
        head:append(gurt.create("span", { text = d.status, class=pillClass }))
        wrap:append(head)

        if d.status == "Pending" then
            wrap:append(gurt.create("pre", {
                text = "Add TXT record:\n"
                     .."Name: "..(d.txt_name or "_gurtmail-verify").."\n"
                     .."Type: TXT\n"
                     .."Value: "..(d.txt_value or "")
            }))
            local btn = gurt.create("button", {
                text="Check verification",
                style="bg-blue-500 text-white rounded px-3 py-1 mt-2"
            })
            btn:on("click", function()
                local resp = api("/api/domains/"..d.id.."/verify", { method="POST" })
                if resp.verified then
                    trace.log("Domain "..d.fqdn.." verified!")
                else
                    trace.warn("Still pending for "..d.fqdn)
                end
                refreshDomains()
            end)
            wrap:append(btn)
        elseif d.status == "Verified" then
            local row = gurt.create("div", { style="flex gap-2 mt-2" })
            local lp  = gurt.create("input", { placeholder="local part (e.g. info)" })
            local un  = gurt.create("input", { placeholder="assign to username" })
            local btn = gurt.create("button", {
                text="Create address",
                style="bg-green-600 text-white rounded px-2"
            })
            btn:on("click", function()
                local resp = api("/api/domains/"..d.id.."/addresses", {
                    method="POST",
                    body=JSON.stringify({ local_part=lp.value, username=un.value })
                })
                if resp and resp.email then
                    trace.log("Created address: "..resp.email)
                    refreshAddresses()
                end
            end)
            row:append(lp); row:append(un); row:append(btn)
            wrap:append(row)
        end

        domainsEl:append(wrap)
    end
end

local function refreshAddresses()
    local list = api("/api/addresses")
    clearChildren(addressesEl)
    addrCount.text = tostring(#list)

    for _, a in ipairs(list) do
        addressesEl:append(gurt.create("div", {
            text = a.email.." (id="..a.id..")",
            style="bg-slate-900 p-2 rounded"
        }))
    end

    -- optional: auto-fill the "from" input with the first address
    if #list > 0 then
        fromAddr.value = list[1].email
    end
end

local function refreshInbox()
    local list = api("/api/messages/inbox")
    clearChildren(inboxEl)
    for _, m in ipairs(list) do
        local msg = gurt.create("div", { class="message" })
        msg.text = (m.subject or "(no subject)").." from "..m.from_email.." → "..m.to_email.."\n"..m.body
        inboxEl:append(msg)
    end
end

local function refreshOutbox()
    local list = api("/api/messages/outbox")
    clearChildren(outboxEl)
    for _, m in ipairs(list) do
        local msg = gurt.create("div", { class="message" })
        msg.text = (m.subject or "(no subject)").." to "..m.to_email.."\n"..m.body
        outboxEl:append(msg)
    end
end

-- session save
local function saveSession()
    gurt.crumbs.set({ name=LS_TOKEN, value=token, lifespan=43000 })
    gurt.crumbs.set({ name=LS_USER, value=userId, lifespan=43000 })
    gurt.crumbs.set({ name=LS_UNAME, value=uname, lifespan=43000 })
end

-- auth events
gurt.select("#register"):on("click", function()
    local data = api("/api/auth/register", {
        method="POST",
        body=JSON.stringify({ username=username.value, password=password.value })
    })
    if not data then return end
    token, userId, uname = data.token, data.user_id, data.username
    saveSession()
    setAuthState()
    refreshDomains(); refreshAddresses(); refreshInbox(); refreshOutbox()
end)

gurt.select("#login"):on("click", function()
    local data = api("/api/auth/login", {
        method="POST",
        body=JSON.stringify({ username=username.value, password=password.value })
    })
    if not data then return end
    token, userId, uname = data.token, data.user_id, data.username
    saveSession()
    setAuthState()
    refreshDomains(); refreshAddresses(); refreshInbox(); refreshOutbox()
end)

-- add domain
gurt.select("#addDomain"):on("click", function()
    local resp = api("/api/domains", {
        method="POST",
        body=JSON.stringify({ fqdn=fqdnInput.value })
    })
    if resp then
        trace.log("Add TXT for "..resp.fqdn.." → Name: "..(resp.txt_name or "_gurtmail-verify").." Value: "..(resp.txt_value or ""))
    end
    refreshDomains()
end)

-- refresh buttons
gurt.select("#refreshAddrs"):on("click", refreshAddresses)
gurt.select("#refreshInbox"):on("click", refreshInbox)
gurt.select("#refreshOutbox"):on("click", refreshOutbox)

-- send
gurt.select("#send"):on("click", function()
    api("/api/messages", {
        method="POST",
        body=JSON.stringify({
            from_address = fromAddr.value, -- changed to email string
            to      = toInput.value,
            subject = subjectInput.value,
            body    = bodyInput.value
        })
    })
    refreshOutbox()
    subjectInput.value = ""
    bodyInput.value = ""
end)

-- startup
setAuthState()
if token ~= "" then
    refreshDomains()
    refreshAddresses()
    refreshInbox()
    refreshOutbox()
end