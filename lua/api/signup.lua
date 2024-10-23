function handle_request(request)
    return {
        status = 200,
        headers = {},
        body = request.path
    }
end
