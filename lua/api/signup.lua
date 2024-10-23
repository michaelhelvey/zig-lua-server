function handle_request(request)
    print("lua: received request at " .. request.url.path)
    print(request.url.params)
    return {
        status = 200,
        headers = {},
        body = "blah"
    }
end
