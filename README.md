`CurlHTTP` is a wrapper around [LibCURL](https://github.com/JuliaWeb/LibCURL.jl) that provides a more Julia like interface to doing HTTP via `Curl`.

[![GH Build](https://github.com/bluesmoon/CurlHTTP.jl/workflows/CI/badge.svg)](https://github.com/bluesmoon/CurlHTTP.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage Status](https://coveralls.io/repos/github/bluesmoon/CurlHTTP.jl/badge.svg?branch=)](https://coveralls.io/github/bluesmoon/CurlHTTP.jl?branch=)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://bluesmoon.github.io/CurlHTTP.jl/)

In particular, this module implements the `CurlEasy` and `CurlMulti` interfaces for curl, and allows using Client TLS certificates.

This module reexports `LibCURL` so everything available in `LibCURL` will be available when this module is used.

See https://curl.se/libcurl/c/libcurl-tutorial.html for a tutorial on using libcurl in C. The Julia interface should be similar.

# Other options for HTTP in Julia

* HTTP.jl - pure Julia
   * Supports client and server mode as well as websockets
   * Complicated to do mutual TLS certificates
   * No single-threaded parallel requests
* Downloads.jl - wraps LibCurl.jl
   * Limited HTTP functionality
   * No single-threaded parallel requests
   * Maintained and used by Pkg.jl
* CurlHTTP.jl (this package) - wraps LibCurl.jl
   * Easy mutual TLS
   * Single-threaded parallel requests
   * Response streaming to a callback function or IOStream

# Examples

## GET a URL and read the response from the internal buffer
```julia
    using CurlHTTP

    curl = CurlEasy(
        url="https://postman-echo.com/get?foo=bar",
        method=CurlHTTP.GET,
        verbose=true
    )

    res, http_status, errormessage = curl_execute(curl)


    # curl.userdata[:databuffer] is a Vector{UInt8} containing the bytes of the response
    responseBody = String(curl.userdata[:databuffer])

    # curl.userdata[:responseHeaders] is a Vector{String} containing the response headers
    responseHeaders = curl.userdata[:responseHeaders]
```


## POST to a URL and read the response with your own callback
```julia
    using CurlHTTP

    curl = CurlEasy(
        url="https://postman-echo.com/post",
        method=CurlHTTP.POST,
        verbose=true
    )

    requestBody = "{\"testName\":\"test_writeCB\"}"
    headers = ["Content-Type: application/json"]

    databuffer = UInt8[]

    res, http_status, errormessage = curl_execute(curl, requestBody, headers) do d
        if isa(d, Array{UInt8})
            append!(databuffer, d)
        end
    end

    responseBody = String(databuffer)
```

## Multiple concurrent requests using CurlMulti
```julia
    using CurlHTTP

    curl = CurlMulti()

    for i in 1:3
        local easy = CurlEasy(
            url="https://postman-echo.com/post?val=$i",
            method=CurlHTTP.POST,
            verbose=true,
        )

        requestBody = "{\"testName\":\"test_multi_writeCB\",\"value\":$i}"
        headers     = ["Content-Type: application/json", "X-App-Value: $(i*5)"]

        CurlHTTP.curl_setup_request_response(
            easy,
            requestBody,
            headers
        )

        curl_multi_add_handle(curl, easy)
    end

    res = curl_execute(curl)

    responses = [p.userdata for p in curl.pool]  # userdata contains response data, status code and error message
```

# External links about CurlHTTP

* [Slides from JuliaCon 2024](https://speakerdeck.com/bluesmoon/curling-with-julia)
* [Video from JuliaCon 2024](https://www.youtube.com/watch?v=x9_qyfZ9PfA)
* [CAJUN Meetup](https://www.meetup.com/julia-cajun/events/299775540/)
