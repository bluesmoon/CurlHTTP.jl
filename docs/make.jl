using Documenter, CurlHTTP

makedocs(
    sitename="CurlHTTP.jl Documentation",
    format=Documenter.HTML(
        prettyurls = false,
        edit_link="main",
    ),
    modules=[CurlHTTP],
)

deploydocs(
    repo = "github.com/bluesmoon/CurlHTTP.jl.git",
)
