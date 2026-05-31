def _gleam_test_impl(ctx):
    srcs = ctx.files.srcs
    deps = ctx.files.deps
    gleam_toml = ctx.file.gleam_toml
    
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    
    ctx.actions.write(
        output = script,
        content = """#!/bin/bash
set -e
export HOME=/tmp
cd /home/rickyraz/objectives/oxion/{package}
gleam test
""".format(package = ctx.label.package),
        is_executable = True,
    )
    
    runfiles = ctx.runfiles(files = srcs + deps + [gleam_toml])
    
    return [DefaultInfo(
        executable = script,
        runfiles = runfiles,
    )]

gleam_test = rule(
    implementation = _gleam_test_impl,
    test = True,
    attrs = {
        "srcs": attr.label_list(allow_files = [".gleam"]),
        "deps": attr.label_list(allow_files = True),
        "gleam_toml": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
    },
)
