do

local NUM_MSG_MAX = 5
local TIME_CHECK = 4

local function user_print_name(user)
  if user.print_name then
    return user.print_name
  end

  local text = ''
  if user.first_name then
    text = user.last_name..' '
  end
  if user.lastname then
    text = text..user.last_name
  end

  return text
end

local function get_msgs_user_chat(user_id, chat_id)
  local user_info = {}
  local uhash = 'User:'..user_id
  local user = redis:hgetall(uhash)
  local um_hash = 'MSGs:'..user_id..':'..chat_id
  user_info.msgs = tonumber(redis:get(um_hash) or 0)
  user_info.name = user_print_name(user)..' ('..user_id..')'
  return user_info
end

local function chat_stats(chat_id)
  local hash = 'Groups:'..chat_id..':Users'
  local users = redis:smembers(hash)
  local users_info = {}

  for i = 1, #users do
    local user_id = users[i]
    local user_info = get_msgs_user_chat(user_id, chat_id)
    table.insert(users_info, user_info)
  end

  table.sort(users_info, function(a, b) 
      if a.msgs and b.msgs then
        return a.msgs > b.msgs
      end
    end)

  local text = ''
  for k,user in pairs(users_info) do
    text = text..user.name..' msg: '..user.msgs..'\n'
  end

  return text
end

local function pre_process(msg)
  if msg.service then
    print('Service message')
    return msg
  end

  if msg.from.type == 'user' then
    local hash = 'user:'..msg.from.id
    print('Saving user', hash)
    if msg.from.print_name then
      redis:hset(hash, 'print_name', msg.from.print_name)
    end
    if msg.from.first_name then
      redis:hset(hash, 'first_name', msg.from.first_name)
    end
    if msg.from.last_name then
      redis:hset(hash, 'last_name', msg.from.last_name)
    end
  end

  if msg.to.type == 'chat' then
    local hash = 'Groups:'..msg.to.id..':Users'
    redis:sadd(hash, msg.from.id)
  end

  local hash = 'MSGs:'..msg.from.id..':'..msg.to.id
  redis:incr(hash)

  if msg.from.type == 'user' then
    local hash = 'user:'..msg.from.id..':msgs'
    local msgs = tonumber(redis:get(hash) or 0)
    if msgs > NUM_MSG_MAX then
      print('User '..msg.from.id..'is Flooding '..msgs)
      msg = nil
    end
    redis:setex(hash, TIME_CHECK, msgs+1)
  end

  return msg
end

local function bot_stats()

  local redis_scan = [[
    local cursor = '0'
    local count = 0

    repeat
      local r = redis.call("SCAN", cursor, "MATCH", KEYS[1])
      cursor = r[1]
      count = count + #r[2]
    until cursor == '0'
    return count]]

  -- Users
  local hash = 'MSGs:*:'..our_id
  local r = redis:eval(redis_scan, 1, hash)
  local text = 'Users: '..r

  hash = 'chat:*:users'
  r = redis:eval(redis_scan, 1, hash)
  text = text..'\nChats: '..r

  return text

end

local function run(msg, matches)
  if matches[1]:lower() == "stats" then

    if not matches[2] then
      if msg.to.type == 'chat' then
        local chat_id = msg.to.id
        return chat_stats(chat_id)
      else
        return 'Works in Group'
      end
    end

    if matches[2] == "bot" then
      if not is_sudo(msg) then
        return "You Are Not Admin"
      else
        return bot_stats()
      end
    end

    if matches[2] == "chat" then
      if not is_sudo(msg) then
        return "You Are Not Admin"
      else
        return chat_stats(matches[3])
      end
    end
  end
end

return {
  description = "Users, Groups and Robot Stats", 
  usage = {
    "!stats : Member Stats (User and Number of Messages)",
    "!stats chat <Group ID> : Group Stats",
    "!stats bot : Robot Stats"
  },
  patterns = {
    "^!([Ss]tats)$",
    "^!([Ss]tats) (chat) (%d+)",
    "^!([Ss]tats) (bot)"
    }, 
  run = run,
  pre_process = pre_process
}

end
