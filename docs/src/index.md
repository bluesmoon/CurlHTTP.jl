# CurlHTTP.jl Documentation

```@docs
CurlHTTP
```

## Globals
```@docs
CurlHTTP.DEFAULT_USER_AGENT
```

## Exported Types
```@docs
CurlHandle
CurlEasy
CurlMulti
```

## Internal Types
```@docs
CurlHTTP.HTTPMethod
CurlHTTP.ChannelMarkers
```

## Exported Methods
```@autodocs
Modules=[CurlHTTP]
Order=[:function]
Filter=f -> which(CurlHTTP, Symbol(f)) == CurlHTTP
Private=false
```

## Methods extended from `LibCURL`
```@autodocs
Modules=[CurlHTTP]
Order=[:function]
Filter=f -> which(CurlHTTP, Symbol(f)) == LibCURL
Private=false
```

## Internal Methods
```@autodocs
Modules=[CurlHTTP]
Order=[:function]
Public=false
```

## Index
```@index
```
