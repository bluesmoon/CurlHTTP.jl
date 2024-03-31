using CurlHTTP

const colors = [:light_red, :light_green, :light_yellow]
function make_handler(i::Int)
    return ch -> Base.printstyled("Handle $i: ", String(take!(ch)), "\n"; color=colors[i])
end

pool = map(1:3) do i
    curl = CurlEasy(url="https://postman-echo.com/post?val=$i", method=CurlHTTP.POST)
    requestBody = """{"testName":"test_multiPOST","value":$i}"""

    curl.userdata[:index]   = i             # userdata is a Dict to store anything you want
    curl.userdata[:channel] = Channel(make_handler(i), Inf)

    CurlHTTP.curl_setup_request(curl, requestBody, ["Content-Type: application/json"];
        data_channel = curl.userdata[:channel]
    )
    return curl
end

# Set up tasks to handle the data channels before calling curl_execute

multi = CurlMulti(pool)
res = curl_execute(multi)
