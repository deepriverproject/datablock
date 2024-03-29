MODEM_SIDE = "top"
DATABASE_FILE = "example_database.txt"
PROTOCOL = "DBDB"
HOSTNAME = "WORKGROUP"
READ_ONLY = false

USER_NAME = "DB_USER"
USER_PASS = "default"

-- WARNING: Encryption only protects against replay attacks, but does not protect against reading the sent commands and the recieved data
ENABLE_ENCRYPTION = true
ENCRYPTION_KEY = "9f8jhf98hu9f48jf934u8fhe9"
CLIENT_CHAL_CODES = {}

require "datablockdb"
db = DataBlockDB:new(nil, DATABASE_FILE)
math.randomseed(os.time())

function encrypt(data)
    local ciphertext = ""
    local _ = 1
    data = ""..data
    for c in data:gmatch"." do
        ciphertext = ciphertext .. (bit.bxor(string.byte(c), string.byte(string.sub(ENCRYPTION_KEY,_,_)))) .. ","
        _ = _ + 1
    end
    return string.sub(ciphertext, 1,-2)
end

function decrypt(data)
    local plaintext = ""
    local _ = 1
    data = ""..data
    for c in data:gmatch"([^,]+)" do
        if c == nil then
            return nil
        end
        plaintext = plaintext .. string.char(bit.bxor(tonumber(c), string.byte(string.sub(ENCRYPTION_KEY,_,_))))
        _ = _ + 1
    end
    return plaintext
end

function table_length(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

function split_string(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
            table.insert(t, str)
    end
    return t
end

function generate_challenge_code(size)
    --size = size or 3
    return math.random(100, 999)
end

function log(client_id, message)
    print("[Client #"..client_id.."] "..message)
    return true
end

function main()
    rednet.open(MODEM_SIDE)
    local event, sender, message, protocol = os.pullEvent("rednet_message")
    if protocol ~= PROTOCOL then
        log(sender, "Failed to connected with protocol "..protocol)
        return false
    end
    log(sender, "Connected with protocol "..protocol)

    msg_split = split_string(message, ' ')
    if message == "CHALLENGE" then
        log(sender, "Generated new challenge code")
        CLIENT_CHAL_CODES[sender] = generate_challenge_code(3)
        rednet.send(sender, CLIENT_CHAL_CODES[sender], PROTOCOL)
        return true
    end

    if ENABLE_ENCRYPTION and CLIENT_CHAL_CODES[sender] == nil then
        log(sender, "No challenge code found")
        rednet.send(sender, "NO_CHALLENGE_CODE", PROTOCOL)
        return false
    end
    local raw_user, raw_pass = msg_split[1], msg_split[2]

    if ENABLE_ENCRYPTION then
        raw_pass = decrypt(raw_pass)
        if raw_pass == nil then
            log(sender, "Sent invalid credentials")
            rednet.send(sender, "INVALID_CREDENTIALS", PROTOCOL)
            return false
        end
        -- TODO: Add password length requirements 
        local raw_pass_challenge, raw_pass_real = string.sub(raw_pass, -3, -1), string.sub(raw_pass, 1, -4)
        if raw_user ~= USER_NAME or raw_pass_real ~= USER_PASS or tonumber(raw_pass_challenge) ~= CLIENT_CHAL_CODES[sender] then
            log(sender, "Sent invalid credentials")
            rednet.send(sender, "INVALID_CREDENTIALS", PROTOCOL)
            return false
        end
    else
        if raw_user ~= USER_NAME or raw_pass ~= USER_PASS then
            log(sender, "Sent invalid credentials")
            rednet.send(sender, "INVALID_CREDENTIALS", PROTOCOL)
            return false
        end
    end
    CLIENT_CHAL_CODES[sender] = nil
    table.remove(msg_split, 1)
    table.remove(msg_split, 1)
    client_handler(sender, msg_split)
end

function client_handler(sender, message)
    if message[1] == "CONNECT" then
        log(sender, "Sent CONNECT check")
        rednet.send(sender, "SUCCESS", PROTOCOL)
        return true
    end

    if message[1] == "HEADERS" then
        log(sender, "Sent HEADERS")
        local headers_parsed = {}
        for _ =1,db:table_length(db._headers) do
            for key, value in pairs(db._headers) do
                if value == _ then
                    table.insert(headers_parsed, key)
                end
            end
        end

        rednet.send(sender, headers_parsed, PROTOCOL)
        return true
    end

    if message[1] == "GET_ROW_BY_HEADER" then
        log(sender, "Sent GET_ROW_BY_HEADER")
        if #message < 3 then
            rednet.send(sender, "INVALID_SYNTAX", PROTOCOL)
            log(sender, "Invalid syntax")
            return false
        end
        rednet.send(sender, db:find_row_by_header(tostring(message[2]),tostring(message[3])), PROTOCOL)
        return true
    end
    
    if message[1] == "GET_ROWS_BY_HEADER" then
        log(sender, "Sent GET_ROWS_BY_HEADER")
        if #message < 3 then
            rednet.send(sender, "INVALID_SYNTAX", PROTOCOL)
            log(sender, "Invalid syntax")
            return false
        end
        rednet.send(sender, db:find_rows_by_header(tostring(message[2]),tostring(message[3])), PROTOCOL)
        return true
    end

    if message[1] == "GET_ALL_ROWS" then
        log(sender, "Sent GET_ALL_ROWS")
        rednet.send(sender, db._db, PROTOCOL)
        return true
    end

    if message[1] == "DELETE_ROW_BY_HEADER" then
        log(sender, "Sent DELETE_ROW_BY_HEADER")
        if #message < 3 then
            rednet.send(sender, "INVALID_SYNTAX", PROTOCOL)
            log(sender, "Invalid syntax")
            return false
        end
        rednet.send(sender, db:delete_row_by_header(tostring(message[2]),tostring(message[3])), PROTOCOL)
        return true
    end

    if message[1] == "UPDATE_ROW_BY_HEADER" then
        log(sender, "Sent UPDATE_ROW_BY_HEADER")
        if #message < 5 then
            rednet.send(sender, "INVALID_SYNTAX", PROTOCOL)
            log(sender, "Invalid syntax")
            return false
        end
        rednet.send(sender, db:update_row_by_header(tostring(message[2]),tostring(message[3]), tostring(message[4]), tostring(message[5])), PROTOCOL)
        return true
    end

    if message[1] == "INSERT" then
        log(sender, "Sent INSERT")
        if #message < 2 then
            rednet.send(sender, "INVALID_SYNTAX", PROTOCOL)
            log(sender, "Invalid syntax")
            return false
        end
        
        rednet.send(sender, db:insert(split_string(message[2], ',')), PROTOCOL)
        return true
    end
end

log("SERVER", "Started listening...")
while true do
    main()
end