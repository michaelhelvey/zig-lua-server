function handle_request(request)
    print("received request at " .. request["path"])

    print("nested headers dict in request")
    for k,v in pairs(request["headers"]) do
        print("key = " .. k .. ", val = " .. v)
    end

    users = utils.sqlite3_query("select * from users;");

    return {
        status = 200,
        headers = {
            ["content-type"] = "application/json"
        },
        body = utils.json({
            users = users,
        })
    }
end
