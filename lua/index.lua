print("I am a lua file that is being invoked")

function handle_request(request)
    print("received request at " .. request["path"])
    return {
        status = 200,
        body = "got your request in lua: '" .. request.body .. "'"
    }
end
