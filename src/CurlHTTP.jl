"""
Wrapper around [`LibCURL`](https://github.com/JuliaWeb/LibCURL.jl) to make it more Julia like.

This module reexports `LibCURL` so everything available in `LibCURL` will be available when this module is used.

See https://curl.se/libcurl/c/libcurl-tutorial.html for a tutorial on using libcurl in C. The Julia interface should be similar.

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
        url="https://postman-echo.com/post?val=\$i",
        method=CurlHTTP.POST,
        verbose=true,
    )

    requestBody = "{\"testName\":\"test_multi_writeCB\",\"value\":\$i}"
    headers     = ["Content-Type: application/json", "X-App-Value: \$(i*5)"]

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
"""
module CurlHTTP

using Reexport
using UUIDs
using NetworkOptions
@reexport using LibCURL

export
    curl_url_escape,
    curl_add_headers,
    curl_setup_request,
    curl_execute,
    curl_cleanup,
    curl_perform,
    curl_response_status,
    curl_error_to_string,
    CurlHandle,
    CurlEasy,
    CurlMulti

function __init__()
    curl_global_init(CURL_GLOBAL_ALL)
end

"""
HTTP Methods recognized by `CurlHTTP`. Current values are:
* _GET_: Make a GET request
* _POST_: Upload data using POST
* _HEAD_: Make a HEAD request and specify no response body
* _DELETE_: Make a DELETE request
* _PUT_: Currently not supported
* _OPTIONS_: Make an OPTIONS request
"""
@enum HTTPMethod GET=1 POST=2 HEAD=3 DELETE=4 PUT=5 OPTIONS=6

"""
Internal markers for the data channel
"""
@enum ChannelMarkers EOF=-1

const CRLF = UInt8.(['\r', '\n'])
const VERBOSE_INFO = [CURLINFO_TEXT, CURLINFO_HEADER_IN, CURLINFO_HEADER_OUT, CURLINFO_SSL_DATA_IN, CURLINFO_SSL_DATA_OUT]

"""
Default user agent to use if not otherwise specified. This allows an application to set the user agent string
at __init__ time rather than at constructor time.

Use [`CurlHTTP.setDefaultUserAgent()`](@ref) to set it. Set it to `nothing` to unset it.
"""
DEFAULT_USER_AGENT = nothing

"""
Set the default user agent string to use for all requests. Set this to `nothing` to disable setting the user agent string.
"""
setDefaultUserAgent(ua::Union{AbstractString, Nothing}) = global DEFAULT_USER_AGENT = ua


"""
Abstract type representing all types of Curl Handles. Currently `CurlEasy` and `CurlMulti`.
"""
abstract type CurlHandle end

"""
Wrapper around a `curl_easy` handle. This is what we get from calling `curl_easy_init`.

Most `curl_easy_*` functions will work on a `CurlEasy` object without any other changes.

## Summary
`struct CurlEasy <:` [`CurlHandle`](@ref)

## Fields
`handle::Ptr`
: A C pointer to the curl_easy handle

`headers::Ptr`
: A C pointer to the list of headers passed on to curl. We hold onto this to make sure we can free allocated memory when required.

`uuid::UUID`
: A unique identifier for this curl handle. Used internally to identify a handle within a pool.

`userdata::Dict`
: A dictionary of user specified data. You may add anything you want to this and it will be passed along with the curl handle to all functions.
  This dictionary will also be populated by several convenience functions to add the `:http_status`, `:errormessage`, and response header (`:databuffer`).
  All data added by internal code will use `Symbol` keys.

## Constructors
`CurlEasy(curl::Ptr)`

Create a `CurlEasy` wrapper around an existing `LibCURL` `curl` handle.

```
CurlEasy(;
    url::String,
    method::`[`HTTPMethod`](@ref)`,
    verbose::Bool,
    certpath::String,
    keypath::String,
    cacertpath::String,
    useragent::String|Nothing
)
```

Create a new `curl` object with default settings and wrap it.

The default settings are:
   * FOLLOWLOCATION
   * SSL_VERIFYPEER
   * SSL_VERIFYHOST
   * SSL_VERSION (highest possible up to TLS 1.3)
   * HTTP_VERSION (H2 over TLS or HTTP/1.1)
   * TCP_FASTOPEN disabled
   * TCP_KEEPALIVE
   * ACCEPT_ENCODING best supported
   * DNS_CACHE_TIMEOUT disabled

Additionally the following options are set based on passed in parameters:
   * POST if `method` is POST
   * HTTPGET if `method` is GET
   * NOBODY if `method` is HEAD
   * CUSTOMREQUEST if `method` is HEAD, DELETE, or OPTIONS
   * VERBOSE if `verbose` is true
   * SSLCERT if `certpath` is set
   * SSLKEY if `certpath` and `keypath` are set
   * CAINFO defaults to `NetworkOptions.ca_roots()` but can be overridden with `cacertpath`
   * URL if `url` is set
   * USERAGENT if `useragent` is set to something other than `nothing`.
"""
mutable struct CurlEasy <: CurlHandle
    handle::Ptr
    headers::Ptr
    uuid::UUID
    userdata::Dict

    CurlEasy(curl::Ptr) = finalizer(curl_cleanup, new(curl, C_NULL, UUIDs.uuid1(), Dict()))

    function CurlEasy(;
        url::AbstractString                       = "",
        method::HTTPMethod                        = GET,
        verbose::Bool                             = false,
        certpath::AbstractString                  = "",
        keypath::AbstractString                   = "",
        cacertpath::AbstractString                = "",
        useragent::Union{AbstractString, Nothing} = DEFAULT_USER_AGENT
    )
        curl = curl_easy_init()

        if method == GET
            curl_easy_setopt(curl, CURLOPT_HTTPGET,       1)     # Use HTTP Get
        elseif method == POST
            curl_easy_setopt(curl, CURLOPT_POST,          1)     # Use HTTP Post
        elseif method == HEAD
            curl_easy_setopt(curl, CURLOPT_NOBODY,        1)     # Use HTTP Head
        elseif method == DELETE
            curl_easy_setopt(curl, CURLOPT_HTTPGET,       1)     # Use HTTP Delete
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE")
        elseif method == OPTIONS
            curl_easy_setopt(curl, CURLOPT_HTTPGET,       1)     # Use HTTP Options
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "OPTIONS")
        else
            throw(ArgumentError("Method `$method' is not currently supported"))
        end

        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION,    1)     # Follow HTTP redirects
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER,    1)     # Verify the peer's SSL cert
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST,    2)     # Verify the server's Common Name
        curl_easy_setopt(curl, CURLOPT_SSLVERSION,        7<<16) # Try highest version up to TLS 1.3
        curl_easy_setopt(curl, CURLOPT_HTTP_VERSION,      4)     # Use H2 over SSL or HTTP/1.1 otherwise
        curl_easy_setopt(curl, CURLOPT_TCP_FASTOPEN,      0)     # Do not use TCP Fastopen since it prevents connection reuse
        curl_easy_setopt(curl, CURLOPT_TCP_KEEPALIVE,     1)     # Use TCP Keepalive
        curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING,   "")    # Use best supported encoding (compression) method. gzip or deflate
        curl_easy_setopt(curl, CURLOPT_DNS_CACHE_TIMEOUT, 0)     # Do not cache DNS in curl

        if !isnothing(useragent)
            curl_easy_setopt(curl, CURLOPT_USERAGENT, useragent)
        end

        # Do we want verbose logging to stderr
        curl_easy_setopt(curl, CURLOPT_VERBOSE, verbose ? 1 : 0)

        # If config has a client cert, use it
        if !isempty(certpath)
            if !isfile(certpath)
                throw(ArgumentError("Could not find the certpath `$certpath'"))
            end
            curl_easy_setopt(curl, CURLOPT_SSLCERT, certpath)
            # Client certs will need cert private key
            if !isempty(keypath)
                if !isfile(keypath)
                    throw(ArgumentError("Could not find the keypath `$keypath'"))
                end
                curl_easy_setopt(curl, CURLOPT_SSLKEY, keypath)
            end
        end

        # If config has a cacert (for self-signed servers), use it
        if !isempty(cacertpath)
            if !isfile(cacertpath)
                throw(ArgumentError("Could not find the cacertpath `$cacertpath'"))
            end
            curl_easy_setopt(curl, CURLOPT_CAINFO, cacertpath)
        elseif !isnothing(NetworkOptions.ca_roots())
            curl_easy_setopt(curl, CURLOPT_CAINFO, NetworkOptions.ca_roots())
        end


        if !isempty(url)
            curl_easy_setopt(curl, CURLOPT_URL, url)
        end

        return CurlEasy(curl)
    end
end


"""
Wrapper around a `curl_multi` handle. This is what we get from calling `curl_multi_init`

## Summary
`struct CurlMulti <:` [`CurlHandle`](@ref)

## Fields
`handle::Ptr`
: A C pointer to the curl_multi handle

`pool::`[`CurlEasy`](@ref)`[]`
: An array of [`CurlEasy`](@ref) handles that are added to this `CurlMulti` handle. These can be added via the constructor or via a call to `curl_multi_add_handle`, and
  may be removed via a call to `curl_multi_remove_handle`.

## Constructors
`CurlMulti()`
: Default constructor that calls `curl_multi_init` and sets up an empty pool

`CurlMulti(::`[`CurlEasy`](@ref)`[])`
: Constructor that accepts a Vector of [`CurlEasy`](@ref) objects, creates a `curl_multi` handle, and adds the easy handles to it.
"""
mutable struct CurlMulti <: CurlHandle
    handle::Ptr
    pool::Vector{CurlEasy}

    CurlMulti() = finalizer(curl_cleanup, new(curl_multi_init(), CurlEasy[]))

    function CurlMulti(pool::Vector{CurlEasy})
        multi = CurlMulti()
        for easy in pool
             curl_multi_add_handle(multi.handle, easy.handle)
             push!(multi.pool, easy)
        end

        multi
    end
end

"""
Cleanup everything created by the [`CurlEasy`](@ref) constructor. See the [upstream docs](https://curl.se/libcurl/c/curl_easy_cleanup.html) for more details.
"""
LibCURL.curl_easy_cleanup(curl::CurlEasy) = (if curl.headers != C_NULL curl_slist_free_all(curl.headers); curl.headers = C_NULL; end; st=curl_easy_cleanup(curl.handle); curl.handle=C_NULL; st)

"""
Cleanup everything created by the [`CurlMulti`](@ref) constructor. See the [upstream docs](https://curl.se/libcurl/c/curl_multi_cleanup.html) for more details.
"""
LibCURL.curl_multi_cleanup(curl::CurlMulti) = (for easy in curl.pool curl_multi_remove_handle(curl.handle, easy.handle); curl_easy_cleanup(easy); end; empty!(curl.pool); curl_multi_cleanup(curl.handle))

"""
Perform a [`CurlEasy`](@ref) transfer synchronously. See the [upstream docs](https://curl.se/libcurl/c/curl_easy_perform.html) for more details.
"""
LibCURL.curl_easy_perform(curl::CurlEasy) = (res = curl_easy_perform(curl.handle); if !isnothing(get(curl.userdata, :data_channel, nothing)) put!(curl.userdata[:data_channel], EOF); end; res)



"""
Set options for the [`CurlEasy`](@ref) handle. See the [upstream docs](https://curl.se/libcurl/c/curl_easy_setopt.html) for all possible options, and links to documentation for each option.
"""
LibCURL.curl_easy_setopt(curl::CurlEasy, opt::Any, ptrval::Integer) = curl_easy_setopt(curl.handle, opt, ptrval)
LibCURL.curl_easy_setopt(curl::CurlEasy, opt::Any, ptrval::Array{T,N} where N) where T = curl_easy_setopt(curl.handle, opt, ptrval)
LibCURL.curl_easy_setopt(curl::CurlEasy, opt::Any, ptrval::Ptr) = curl_easy_setopt(curl.handle, opt, ptrval)
LibCURL.curl_easy_setopt(curl::CurlEasy, opt::Any, ptrval::AbstractString) = curl_easy_setopt(curl.handle, opt, ptrval)
LibCURL.curl_easy_setopt(curl::CurlEasy, opt::Any, param::Any) = curl_easy_setopt(curl.handle, opt, param)

"""
Clone a [`CurlEasy`](@ref) handle. See the [upstream docs](https://curl.se/libcurl/c/curl_easy_duphandle.html) for more details.
"""
LibCURL.curl_easy_duphandle(curl::CurlEasy) = CurlEasy(curl_easy_duphandle(curl.handle))

"""
URL escape a Julia string using a [`CurlEasy`](@ref) handle to make it safe for use as a URL.
See the [upstream docs](https://curl.se/libcurl/c/curl_easy_escape.html)

The return value is a Julia string with memory owned by Julia, so there's no risk of leaking memory.
"""
function LibCURL.curl_easy_escape(curl::CurlEasy, s, l)
    s_esc = curl_easy_escape(curl.handle, s, l)
    s_len = ccall(:strlen, Csize_t, (Ptr{Cvoid}, ), s_esc)
    s_ret = Array{UInt8}(undef, s_len)

    unsafe_copyto!(pointer(s_ret), s_esc, s_len)

    curl_free(s_esc)
    String(s_ret)
end

"""
    curl_url_escape(::CurlEasy, ::String) → String
    curl_url_escape(::String) → String

Use curl to do URL escaping
"""
curl_url_escape(curl::CurlEasy, s::AbstractString) = curl_easy_escape(curl, s, 0)
curl_url_escape(s::AbstractString) = curl_url_escape(CurlEasy(curl_easy_init()), s)

"""
Cleanup the [`CurlHandle`](@ref) automatically determining what needs to be done for `curl_easy` vs `curl_multi` handles.
In general, this will be called automatically when the [`CurlHandle`](@ref) gets garbage collected.
"""
curl_cleanup(curl::CurlEasy)  = curl_easy_cleanup(curl)
curl_cleanup(curl::CurlMulti) = curl_multi_cleanup(curl)

"""
Perform all [`CurlEasy`](@ref) transfers attached to a [`CurlMulti`](@ref) handle asynchronously. See the [upstream docs](https://curl.se/libcurl/c/curl_multi_perform.html) for more details.
"""
LibCURL.curl_multi_perform(curl::CurlMulti, still_running::Ref{Cint}) = curl_multi_perform(curl.handle, still_running)
function LibCURL.curl_multi_perform(curl::CurlMulti)
    still_running = Ref{Cint}(1)

    numfds = Ref{Cint}()

    while still_running[] > 0
        mc = curl_multi_perform(curl, still_running)

        if mc == CURLM_OK
            mc = curl_multi_wait(curl.handle, C_NULL, 0, 1000, numfds)
        end

        if mc != CURLM_OK
            # COV_EXCL_START
            @error "curl_multi failed, code $(mc)."
            return mc
            # COV_EXCL_STOP
        end
    end

    CURLM_OK
end

"""
Run either `curl_easy_perform` or `curl_multi_perform` depending on the type of handle passed in.
"""
curl_perform(curl::CurlEasy)  = curl_easy_perform(curl)
curl_perform(curl::CurlMulti) = curl_multi_perform(curl)

"""
Adds a [`CurlEasy`](@ref) handle to the [`CurlMulti`](@ref) pool. See the [upstream docs](https://curl.se/libcurl/c/curl_multi_add_handle.html)
"""
function LibCURL.curl_multi_add_handle(multi::CurlMulti, easy::CurlEasy)
    push!(multi.pool, easy)
    curl_multi_add_handle(multi.handle, easy.handle)
end

"""
Remove a [`CurlEasy`](@ref) handle from the [`CurlMulti`](@ref) pool. See the [upstream docs](https://curl.se/libcurl/c/curl_multi_remove_handle.html).
Pass in either the [`CurlEasy`](@ref) handle or its `CurlHandle.uuid`.
"""
function LibCURL.curl_multi_remove_handle(multi::CurlMulti, easy::CurlEasy)
    filter!(pool_entry -> pool_entry.uuid != easy.uuid, multi.pool)
    curl_multi_remove_handle(multi.handle, easy.handle)
end
LibCURL.curl_multi_remove_handle(multi::CurlMulti, easy_uuid::AbstractString) = curl_multi_remove_handle(multi, Base.UUID(easy_uuid))
function LibCURL.curl_multi_remove_handle(multi::CurlMulti, easy_uuid::Base.UUID)
    easy = findfirst(pool_entry -> pool_entry.uuid == easy_uuid, multi.pool)
    if isnothing(easy)
        return nothing
    end

    easy = multi.pool[easy]

    curl_multi_remove_handle(multi, easy)
end


"""
Run common housekeeping tasks required by a curl callback function.

This function should be called from a curl WRITE or HEADER callback function. It does the following:

1. Calculate the number of bytes read
2. Copy bytes into a Vector{UInt8}
3. Convert any non-null userdata parameter to a julia type

It then returns a tuple of these three values.
"""
function curl_cb_preamble(curlbuf::Ptr{Cvoid}, s::Csize_t, n::Csize_t, p_ctxt::Ptr{Cvoid})
    sz = s * n
    data = Array{UInt8}(undef, sz)

    ccall(:memcpy, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, UInt64), data, curlbuf, sz)

    if p_ctxt == C_NULL
        j_ctxt = nothing
    else
        j_ctxt = unsafe_pointer_to_objref(p_ctxt)
    end

    (sz, data, j_ctxt)
end

"""
Default write callback that puts the data stream as a `Vector{UInt8}` onto a `Channel` passed in via `curl_easy_setopt(CURLOPT_WRITEDATA)`.

This callback is called by curl when data is available to be read and is set up in [`curl_setup_request`](@ref)
"""
function curl_write_cb(curlbuf::Ptr{Cvoid}, s::Csize_t, n::Csize_t, p_ctxt::Ptr{Cvoid})::Csize_t
    (sz, data, ch) = curl_cb_preamble(curlbuf, s, n, p_ctxt)

    @debug "Body sending $sz bytes"

    put!(ch, data)

    sz::Csize_t
end

"""
Default header callback that puts the current header as a `crlf` terminate `String` onto a `Channel` passed in via `curl_easy_setopt(CURLOPT_HEADERDATA)`.

This callback is called by curl when header data is available to be read and is set up in [`curl_setup_request`](@ref)
"""
function curl_header_cb(curlbuf::Ptr{Cvoid}, s::Csize_t, n::Csize_t, p_ctxt::Ptr{Cvoid})::Csize_t
    (sz, data, ch) = curl_cb_preamble(curlbuf, s, n, p_ctxt)

    headerline = String(data)

    @debug "Header sending $(sz) bytes"

    put!(ch, headerline == "\r\n" ? EOF : headerline)

    sz::Csize_t
end

"""
[Internal] curl debug callback to log informational text, header data, and SSL data transferred over the network.
This will only run if curl is configured in verbose mode.
"""
function curl_debug_cb(curl::Ptr{Cvoid}, type::Cint, curlbuf::Ptr{Cvoid}, sz::Csize_t, p_ctxt::Ptr{Cvoid})::Csize_t
    if type ∉ VERBOSE_INFO
        return Culong(0)
    end

    data = Array{UInt8}(undef, sz)
    ccall(:memcpy, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, UInt64), data, curlbuf, sz)

    @info String(data)

    Culong(0)
end

function _create_default_buffer_handler(curl::CurlEasy, buffername::Symbol, buffertype::DataType=UInt8)
    buffer = curl.userdata[buffername] = buffertype[]

    if isbitstype(buffertype)
        (mtd, expectedtype) = (append!, typeof(buffer))
    else
        (mtd, expectedtype) = (push!, buffertype)
    end

    return data -> if isa(data, expectedtype)
        mtd(buffer, data)
    else
        @warn "$buffername got data of type $(typeof(data)) expected $(expectedtype)"
    end
end


"""
Add a vector of headers to the curl object
"""
function curl_add_headers(curl::CurlEasy, headers::Vector{String}; append::Bool=false)
    if !append && curl.headers != C_NULL
        curl_slist_free_all(curl.headers)
        curl.headers = C_NULL
    end

    for header in headers
        curl.headers = curl_slist_append(curl.headers, header)
    end

    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, curl.headers)

    return curl
end

"""
Prepare a [`CurlEasy`](@ref) object for making a request.

* Adds the `requestBody` and a corresponding `Content-Length`
* Adds headers
* If `data_channel` or `header_channel` are set, then sets up a default WRITE/HEADER callback that writes to that Channel
* If `url` is set, sets the request URL
"""
function curl_setup_request(
    curl::CurlEasy,
    requestBody::String,
    headers::Vector{String} = String[];
    data_channel::Union{Channel,Nothing}   = nothing,
    header_channel::Union{Channel,Nothing} = nothing,
    url::AbstractString                    = ""
)
    if !isempty(url)
        curl_easy_setopt(curl, CURLOPT_URL, url)
    end

    curl_add_headers(curl, headers)

    curl.userdata[:headers] = headers

    if !isempty(requestBody)
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, ncodeunits(requestBody))
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, requestBody)

        curl.userdata[:requestBody] = requestBody

        curl_add_headers(curl, ["Content-Length: $(ncodeunits(requestBody))"]; append=true)
    end

    if !isnothing(data_channel)
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, @cfunction(curl_write_cb, Csize_t, (Ptr{Cvoid}, Csize_t, Csize_t, Ptr{Cvoid})))
        curl_easy_setopt(curl, CURLOPT_WRITEDATA,  Base.unsafe_convert(Ptr{Cvoid}, Base.cconvert(Ptr{Cvoid}, Ref(data_channel))))

        curl.userdata[:data_channel] = data_channel
    end

    if !isnothing(header_channel)
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, @cfunction(curl_header_cb, Csize_t, (Ptr{Cvoid}, Csize_t, Csize_t, Ptr{Cvoid})))
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, Base.unsafe_convert(Ptr{Cvoid}, Base.cconvert(Ptr{Cvoid}, Ref(header_channel))))

        curl.userdata[:header_channel] = header_channel
    end

    # Add a debug handler to log wire transfer data
    curl_easy_setopt(curl, CURLOPT_DEBUGFUNCTION, @cfunction(curl_debug_cb, Csize_t, (Ptr{Cvoid}, Cint, Ptr{Cvoid}, Csize_t, Ptr{Cvoid})))

    errorbuffer = Array{UInt8}(undef, CURL_ERROR_SIZE)
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errorbuffer)

    curl.userdata[:errorbuffer] = errorbuffer

    return curl
end

"""
Setup a Channel for the default response handlers to write to.
"""
function setup_response_handler(data_handler::Function, uuid::UUID)
    @debug "Creating channel for $uuid"
    return Channel() do chnl
        @debug "Starting channel handler for $uuid"

        @debug "Going to read from channel for $uuid"
        for d in chnl
            if d == EOF
                @debug "Removing channel for $uuid"
                close(chnl)
                break
            else
                @debug "Received $(length(d)) bytes"

                data_handler(d)
            end
        end
        @debug "Finished channel handler for $uuid"
    end
end
setup_response_handler(::Nothing, ::Any) = nothing

"""
Setup the request object and response handlers in preparation to execute a request.

When using the [`CurlEasy`](@ref) interface, this method is called internally by [`curl_execute`](@ref), however when using the
[`CurlMulti`](@ref) interface, it is necessary to call this on every [`CurlEasy`](@ref) handle added to the [`CurlMulti`](@ref) handle.

This method allows you to set up your own response data and header handlers that receive streamed data. If you do
not pass in a handler, default handlers will be set up that write binary data as bytes (`Vector{UInt8}`) to 
`curl.userdata[:databuffer]` and an array of String response headers (`Vector{String}`) to `curl.userdata[:responseHeaders]`.

## Arguments
`curl::`[`CurlEasy`](@ref)
: The [`CurlEasy`](@ref) handle to operate on

`requestBody::String`
: Any request body text that should be passed on to the server. Typically used for `POST` requests. Leave this as an empty
  String to skip. This is passed as-is to `curl_setup_request`.

`headers::Vector{String} = String[]`
: Any request headers that should be passed on to the server as part of the request.  Headers SHOULD be of the form `key: value`.
  Consult [RFC 2616 section 4.2](https://datatracker.ietf.org/doc/html/rfc2616#section-4.2) for more details on HTTP request headers.

## Keyword Arguments
`data_handler::Union{Function, Nothing} = <default>`
: A function to handle any response Body data. This function should accept a single argument of type `Vector{UInt8}`. Its return value will be ignored.
  If not specified, a default handler will be used.  Set this explicitly to `nothing` to disable handling of HTTP response body data.

`header_handler::Union{Function, Nothing} = <default>`
: A function to handle any response Header data. This function should accept a single argument of type `String`. Its return value will be ignored.
  If not specified, a default handler will be used.  Set this explicitly to `nothing` to disable handling of HTTP response header data.

`url::AbstractString=""`
: The URL to use for this request. This permanently overrides the `url` passed in to the [`CurlEasy`](@ref) constructor. If not specified, then the previous value
  of the [`CurlEasy`](@ref)'s url is reused.

## Returns

The [`CurlEasy`](@ref) object.
"""
function curl_setup_request_response(
    curl::CurlEasy,
    requestBody::String,
    headers::Vector{String} = String[];
    data_handler::Union{Function, Nothing} = _create_default_buffer_handler(curl, :databuffer),
    header_handler::Union{Function, Nothing} = _create_default_buffer_handler(curl, :responseHeaders, String),
    url::AbstractString = ""
)
    data_channel = setup_response_handler(data_handler, curl.uuid)
    header_channel = setup_response_handler(header_handler, curl.uuid)

    curl_setup_request(
        curl,
        requestBody,
        headers;
        data_channel,
        header_channel,
        url
    )
end

"""
    curl_execute(::CurlMulti) → CURLMcode

Executes all pending [`CurlEasy`](@ref) attached to the [`CurlMulti`](@ref) handle and returns a `CURLMcode` indicating success or failure.

In most cases, this function should return `CURLM_OK` even if there were failures in individual transfers. Each [`CurlEasy`](@ref) handle
will have `curl.userdata[:http_status]` set and `curl.userdata[:errormessage]` will be set in case of an error.

This function will print errors or warnings to the Logger for unexpected states. File a bug if you see any of these.
"""
function curl_execute(curl::CurlMulti)
    res = curl_perform(curl)

    msgq = Ref{Cint}(1)
    while msgq[] > 0
        # Returns a Ptr{LibCURL.CURLMsg}
        m = curl_multi_info_read(curl.handle, msgq)
        if m == C_NULL
            # COV_EXCL_START
            if msgq[] > 0
                @error "curl_multi_info_read returned NULL while $(msgq[]) messages still remain queued"
            end
            break
            # COV_EXCL_STOP
        end

        # Convert from Ptr to LibCURL.CURLMsg
        m_jl = unsafe_load(m)

        if m_jl.msg == CURLMSG_DONE
            local easy_h = m_jl.easy_handle

            local easy = findfirst(x -> x.handle == easy_h, curl.pool)
            if isnothing(easy)
                # COV_EXCL_START
                @error "Couldn't find handle $easy_h"
                continue
                # COV_EXCL_STOP
            end
            easy = curl.pool[easy]

            if haskey(easy.userdata, :data_channel)
                put!(easy.userdata[:data_channel], EOF)
            end

            easy.userdata[:http_status]  = curl_response_status(easy)
            if haskey(easy.userdata, :errorbuffer)
                easy.userdata[:errormessage] = curl_error_to_string(easy.userdata[:errorbuffer])
            end
        else
            @warn "curl_multi_info_read returned an unknown code: $(m_jl.msg)... ignoring. msgq=$(msgq[])"
        end
    end

    res
end


"""
    curl_execute(data_handler::Function, ::CurlEasy, ::String, ::Vector{String}; url::String) → (CURLCode, Int64, String)
    curl_execute(::CurlEasy, ::String, Vector{String}; url::String, data_handler::Function, header_handler::Function)  → (CURLCode, Int64, String)

Execute a [`CurlEasy`](@ref) handle optionally passing in a `requestBody` (for POSTs), any HTTP request headers, a request URL, and handlers for response
data and headers.

In its first form this method accepts the `data_handler` as the first argument allowing you to use `curl_execute(curl) do data ... end` to handle the data.
In this case, response headers are ignored.

In its second form, both data and header handlers are passed in as keyword arguments. If not specified, then default handlers are set up that write to
`curl.userdata[:databuffer]` and `curl.userdata[:responseHeaders]` respectively.  You may explicitly set the handler to `nothing` to avoid handling data or headers.
This can have a small improvement in memory utilization.
"""
curl_execute(
    data_handler::Function,
    curl::CurlEasy,
    requestBody::String="",
    headers::Vector{String}=String[];
    url::AbstractString=""
) = curl_execute(curl, requestBody, headers; data_handler, url, header_handler=nothing)

function curl_execute(
    curl::CurlEasy,
    requestBody::String="",
    headers::Vector{String}=String[];
    data_handler::Union{Function, Nothing} = _create_default_buffer_handler(curl, :databuffer),
    header_handler::Union{Function, Nothing} = _create_default_buffer_handler(curl, :responseHeaders, String),
    url::AbstractString=""
)
    curl_setup_request_response(curl, requestBody, headers; data_handler, header_handler, url)

    @debug "Starting curl_easy_perform"
    res = curl_easy_perform(curl)
    @debug "Finished curl_easy_perform"

    http_status  = curl_response_status(curl)
    errormessage = curl_error_to_string(curl.userdata[:errorbuffer])

    return (res, http_status, errormessage)
end

"""
    curl_error_to_string(::Vector{UInt8}) → String

Convert curl's error message stored as a NULL terminated sequence of bytes into a Julia `String`
"""
function curl_error_to_string(errorbuffer::Vector{UInt8})
    errorend = something(findfirst(==(UInt8(0)), errorbuffer), length(errorbuffer)+1)
    return String(@view(errorbuffer[1:errorend-1]))
end

"""
    curl_response_status(::CurlEasy) → Int64

Get the HTTP status code of the most recent response from the [`CurlEasy`](@ref) object.
"""
function curl_response_status(curl::CurlEasy)
    http_code = Ref{Clong}()
    curl_easy_getinfo(curl.handle, CURLINFO_RESPONSE_CODE, http_code)
    return http_code[]
end

end # module
