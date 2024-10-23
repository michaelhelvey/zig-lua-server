print("I am a lua file that is being invoked")

function handle_request(request)
    print("received request at " .. request["path"])

    print("nested headers dict in request")
    for k,v in pairs(request["headers"]) do
        print("key = " .. k .. ", val = " .. v)
    end

    return {
        status = 200,
        headers = {
            ["content-type"] = "application/json"
        },
        body = utils.json({
            message = "hi from lua - I can write json now!",
            nested = { very = { nestedMore = "indeed" } },
            list = {"some", "list", "of", "stuff", 69},
        })
    }
end
