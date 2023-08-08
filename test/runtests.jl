using CurlHTTP, Test, JSON

gbVerbose = false

function test_GET()
    curl = CurlEasy(
        url="https://postman-echo.com/get?foo=bar&baz=zod",
        method=CurlHTTP.GET,
        verbose=gbVerbose
    )

    databuffer = UInt8[]

    res, http_status, errormessage = curl_execute(curl, "", ["X-Custom-Header: ding"]) do d
        if isa(d, Array{UInt8})
            append!(databuffer, d)
        end
    end

    @test CURLE_OK == res
    @test 200 == http_status
    data = JSON.parse(String(databuffer))
    @test "https://postman-echo.com/get?foo=bar&baz=zod" == data["url"]
    @test Dict("foo" => "bar", "baz" => "zod") == data["args"]
    @test haskey(data["headers"], "x-custom-header")
    @test data["headers"]["x-custom-header"] == "ding"
    @test "" == errormessage
end

function test_GET_debug()
    curl = CurlEasy(
        url="https://postman-echo.com/get?foo=bar&baz=zod",
        method=CurlHTTP.GET,
        verbose=true
    )

    res, http_status, errormessage = curl_execute(curl)

    @test CURLE_OK == res
    @test 200 == http_status
    databuffer = curl.userdata[:databuffer]
    data = JSON.parse(String(databuffer))
    @test "https://postman-echo.com/get?foo=bar&baz=zod" == data["url"]
    @test Dict("foo" => "bar", "baz" => "zod") == data["args"]
    @test "" == errormessage

    responseHeaders = curl.userdata[:responseHeaders]
    @test length(responseHeaders) > 1
end

function test_GET_reuse()
    curl = CurlEasy(
        url="https://postman-echo.com/get?foo=bar&baz=zod",
        method=CurlHTTP.GET,
        verbose=false
    )

    res, http_status, errormessage = curl_execute(curl, "", ["X-Custom-Header: ding1"])

    @test CURLE_OK == res
    @test 200 == http_status
    @test "" == errormessage
    databuffer = curl.userdata[:databuffer]
    data = JSON.parse(String(databuffer))
    @test "https://postman-echo.com/get?foo=bar&baz=zod" == data["url"]
    @test Dict("foo" => "bar", "baz" => "zod") == data["args"]
    @test haskey(data["headers"], "x-custom-header")
    @test data["headers"]["x-custom-header"] == "ding1"
    @test !haskey(data["headers"], "user-agent")

    res, http_status, errormessage = curl_execute(curl, "", ["X-Custom-Header: ding2"]; url="https://postman-echo.com/get?foo=bear&baz=zeroed")

    @test CURLE_OK == res
    @test 200 == http_status
    @test "" == errormessage
    databuffer = curl.userdata[:databuffer]
    data = JSON.parse(String(databuffer))
    @test "https://postman-echo.com/get?foo=bear&baz=zeroed" == data["url"]
    @test Dict("foo" => "bear", "baz" => "zeroed") == data["args"]
    @test haskey(data["headers"], "x-custom-header")
    @test data["headers"]["x-custom-header"] == "ding2"
end

function test_GET_useragent()
    CurlHTTP.setDefaultUserAgent("CurlHTTP/0.1")

    curl = CurlEasy(
        url="https://postman-echo.com/get?foo=bar&baz=zod",
        method=CurlHTTP.GET,
        verbose=gbVerbose
    )

    res, http_status, errormessage = curl_execute(curl)

    @test CURLE_OK == res
    @test 200 == http_status
    databuffer = curl.userdata[:databuffer]
    data = JSON.parse(String(databuffer))
    @test "https://postman-echo.com/get?foo=bar&baz=zod" == data["url"]
    @test Dict("foo" => "bar", "baz" => "zod") == data["args"]
    @test "CurlHTTP/0.1" == data["headers"]["user-agent"]
    CurlHTTP.setDefaultUserAgent(nothing)
end

function test_DELETE()
    curl = CurlEasy(
        url="https://postman-echo.com/delete?foo=bar&baz=zod",
        method=CurlHTTP.DELETE,
        verbose=gbVerbose
    )

    databuffer = UInt8[]

    res, http_status, errormessage = curl_execute(curl, "", ["X-Custom-Header: ding"]) do d
        if isa(d, Array{UInt8})
            append!(databuffer, d)
        end
    end

    @test CURLE_OK == res
    @test 200 == http_status
    data = JSON.parse(String(databuffer))
    @test "https://postman-echo.com/delete?foo=bar&baz=zod" == data["url"]
    @test Dict("foo" => "bar", "baz" => "zod") == data["args"]
    @test isnothing(data["json"])
    @test haskey(data["headers"], "x-custom-header")
    @test data["headers"]["x-custom-header"] == "ding"
    @test "" == errormessage
end

function test_OPTIONS()
    curl = CurlEasy(
        url="https://postman-echo.com/get?foo=bar&baz=zod",
        method=CurlHTTP.OPTIONS,
        verbose=gbVerbose
    )

    databuffer = UInt8[]

    res, http_status, errormessage = curl_execute(curl, "", ["X-Custom-Header: ding"]) do d
        if isa(d, Array{UInt8})
            append!(databuffer, d)
        end
    end

    @test CURLE_OK == res
    @test 200 == http_status
    data = String(databuffer)
    @test "GET,HEAD,PUT,POST,DELETE,PATCH" == data
    @test "" == errormessage
end

function test_HEAD()
    curl = CurlEasy(
        url="https://postman-echo.com/get?foo=bar&baz=zod",
        method=CurlHTTP.HEAD,
        verbose=gbVerbose
    )

    databuffer = UInt8[]

    res, http_status, errormessage = curl_execute(curl, "", ["X-Custom-Header: ding"]) do d
        if isa(d, Array{UInt8})
            append!(databuffer, d)
        end
    end

    @test CURLE_OK == res
    @test 200 == http_status
    @test isempty(databuffer)
    @test "" == errormessage
end

function test_PUT()
    @test_throws ArgumentError("Method `PUT' is not currently supported") CurlEasy(method=CurlHTTP.PUT)
end

function test_POST()
    curl = CurlEasy(
        url="https://postman-echo.com/post",
        method=CurlHTTP.POST,
        verbose=gbVerbose
    )

    requestBody = """{"testName":"test_POST"}"""

    errorbuffer = Array{UInt8}(undef, CURL_ERROR_SIZE)
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errorbuffer)

    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, length(requestBody))
    curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, requestBody)

    curl_add_headers(curl, [
        "Content-Type: application/json",
        "Content-Length: $(length(requestBody))"
    ])

    res = curl_perform(curl)

    @test CURLE_OK == res
end

function test_writeCB()
    curl = CurlEasy(
        url="https://postman-echo.com/post",
        method=CurlHTTP.POST,
        verbose=gbVerbose,
        useragent="CurlHTTP Test"
    )

    requestBody = """{"testName":"test_writeCB"}"""
    headers = ["Content-Type: application/json",]

    databuffer = UInt8[]

    res, http_status, errormessage = curl_execute(curl, requestBody, headers) do d
        if isa(d, Array{UInt8})
            append!(databuffer, d)
        end
    end

    @test CURLE_OK == res
    @test 200 == http_status
    @test 2 * length(requestBody) < length(databuffer)  # We expect requestBody to be repeated twice in the response
    data = JSON.parse(String(databuffer))
    reqB = JSON.parse(requestBody)
    @test reqB == data["data"] == data["json"]
    @test "CurlHTTP Test" == data["headers"]["user-agent"]
    @test "" == errormessage
end

function test_headerCB()
end

function test_multiPOST()
    pool = CurlEasy[]

    for i in 1:3
        local curl = CurlEasy(
            url="https://postman-echo.com/post?val=$i",
            method=CurlHTTP.POST,
            verbose=gbVerbose
        )

        local requestBody = """{"testName":"test_multiPOST","value":$i}"""

        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, length(requestBody))
        curl_easy_setopt(curl, CURLOPT_COPYPOSTFIELDS, requestBody)

        curl_add_headers(curl, [
            "Content-Type: application/json",
            "Content-Length: $(length(requestBody))"
        ])

        push!(pool, curl)
    end

    curl = CurlMulti(pool)

    res = curl_execute(curl)

    http_statuses = [p.userdata[:http_status] for p in curl.pool]

    @test CURLM_OK == res
    @test 3 == length(http_statuses)
    @test all(http_statuses .== 200)
end

function test_multi_writeCB()
    curl = CurlMulti()

    for i in 1:3
        local easy = CurlEasy(
            url="https://postman-echo.com/post?val=$i",
            method=CurlHTTP.POST,
            verbose=gbVerbose,
        )

        requestBody = """{"testName":"test_multi_writeCB","value":$i}"""
        headers     = ["Content-Type: application/json", "X-App-Value: $(i*5)"]

        easy.userdata[:i] = i

        CurlHTTP.curl_setup_request_response(
            easy,
            requestBody,
            headers
        )

        curl_multi_add_handle(curl, easy)
    end

    res = curl_execute(curl)

    responses = [p.userdata for p in curl.pool]

    @test CURLM_OK == res
    @test 3 == length(responses)

    @testset "Response $(r[:i])" for r in responses
        @test haskey(r, :http_status)
        @test r[:http_status] == 200

        @test 2 * length(r[:requestBody]) < length(r[:databuffer])

        data = JSON.parse(String(r[:databuffer]))
        reqB = JSON.parse(r[:requestBody])
        @test reqB == data["data"] == data["json"]

        @test haskey(r, :errormessage)
        @test "" == r[:errormessage]
    end
end

function test_Certs()
    @test_throws ArgumentError("Could not find the certpath `foobar'") CurlEasy(certpath="foobar")
    @test_throws ArgumentError("Could not find the keypath `foobar'") CurlEasy(certpath=@__FILE__, keypath="foobar")
    @test CurlEasy(certpath=@__FILE__, keypath=@__FILE__) isa CurlEasy
    @test_throws ArgumentError("Could not find the cacertpath `foobar'") CurlEasy(cacertpath="foobar")
    @test CurlEasy(cacertpath=LibCURL.cacert) isa CurlEasy
end

function test_UrlEscape()
    @test "hello%20world%2C%20how%20are%20you%3F%20I%27m%20fine%21%20%23escape" == curl_url_escape("hello world, how are you? I'm fine! #escape")
end

@testset "Curl" begin
    @testset "GET" begin
        test_GET()
        test_GET_debug()
        test_GET_reuse()
        test_GET_useragent()
    end
    @testset "HEAD" begin test_HEAD() end
    @testset "HEAD" begin test_PUT() end
    @testset "DELETE" begin test_DELETE() end
    @testset "OPTIONS" begin test_OPTIONS() end
    @testset "POST" begin test_POST() end
    @testset "writeCB"   begin test_writeCB()   end
    @testset "headerCB"  begin test_headerCB()  end
    @testset "multiPOST" begin test_multiPOST() end
    @testset "multi writeCB" begin test_multi_writeCB() end
    @testset "Certs" begin test_Certs() end
    @testset "URL Escape" begin test_UrlEscape() end
end
