using CurlHTTP, JSON3

const NoBody = ""

curl = CurlEasy(
    url="https://postman-echo.com/get?foo=bar&baz=zod",
    method=CurlHTTP.GET,
)

databuffer = UInt8[]

res, http_status, errormessage = curl_execute(curl, NoBody, ["X-Custom-Header: ding"]) do d
    append!(databuffer, d)
end

data = JSON3.read(databuffer, Dict{String, Any})


# We can reuse this connection
res, http_status, errormessage = curl_execute(curl, NoBody, ["X-Custom-Header: ding2"]; url="https://postman-echo.com/get?foo=bear&baz=zeroed")
data = JSON3.read(curl.userdata[:databuffer], Dict{String, Any})

curl_cleanup(curl)  # Optional - will run on finalizer
