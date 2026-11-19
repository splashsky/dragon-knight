-- PLACEHOLDER (phase 1): proves the engine stack end-to-end. Phase 2 replaces this file.
local function html(body, status)
  return {
    status = status or 200,
    headers = { { "Content-Type", "text/html; charset=utf-8" } },
    body = body,
  }
end

local function text(body, status)
  return {
    status = status or 200,
    headers = { { "Content-Type", "text/plain; charset=utf-8" } },
    body = body,
  }
end

local routes = {}

routes["/"] = function(req)
  local names = {}
  for k in pairs(req.headers) do names[#names + 1] = k end
  table.sort(names)
  local headers = {}
  for _, k in ipairs(names) do headers[#headers + 1] = { name = k, value = req.headers[k] } end
  return html(dk.render("hello", {
    req = req,
    headers = headers,
    now = os.date("!%Y-%m-%d %H:%M:%S UTC", dk.now()),
    elapsed = string.format("%.3f", (dk.clock() - dk.request_start) * 1000),
  }))
end

routes["/boom"] = function()
  error("boom: this error is intentional")
end

routes["/db"] = function()
  local db = dk.db
  db:exec("CREATE TABLE IF NOT EXISTS hits (id INTEGER PRIMARY KEY, at INTEGER NOT NULL, note TEXT)")
  local _, id = db:exec("INSERT INTO hits (at, note) VALUES (?, ?)", dk.now(), "hit")
  local count = db:value("SELECT count(*) FROM hits")
  local row = db:first("SELECT id, at, note FROM hits WHERE id = ?", id)
  return text(string.format("hits=%d last_id=%d note=%s\n", count, row.id, row.note))
end

routes["/stats"] = function()
  local s = dk.vmstats()
  local keys = {}
  for k in pairs(s) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tostring(s[k]) end
  return text(table.concat(out, "\n") .. "\n")
end

return function(req)
  local route = routes[req.path]
  if not route then
    return html("<h1>404 Not Found</h1>", 404)
  end
  return route(req)
end
