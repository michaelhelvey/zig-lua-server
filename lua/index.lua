function handle_request(request)
    print("method:", request.method)
    print("path: ", request.url.path)

    for k, v in pairs(request.url.params) do
        print("query param: " .. "key = " .. k .. " val = " .. v)
    end

    print("body: ", request.body)

    return {
        status = 200,
        headers = {
            ["X-My-Header"] = "some value"
        },
        body = "here is my body"
    }
end
