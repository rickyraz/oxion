def _gleam_build_impl(ctx):
    srcs = ctx.files.srcs
    deps = ctx.files.deps
    gleam_toml = ctx.file.gleam_toml
    
    out_dir = ctx.actions.declare_directory(ctx.label.name + "_build")
    
    inputs = srcs + deps + [gleam_toml]
    
    ctx.actions.run_shell(
        command = """
            set -e
            export HOME=/tmp
            cd {package}
            gleam build
            mkdir -p {out}
            cp -r build/* {out}/ 2>/dev/null || true
        """.format(
            package = ctx.label.package,
            out = out_dir.path,
        ),
        inputs = inputs,
        outputs = [out_dir],
        mnemonic = "GleamBuild",
        progress_message = "Building Gleam package %{label}",
        use_default_shell_env = True,
        execution_requirements = {"no-sandbox": "1"},
    )
    
    return [DefaultInfo(files = depset([out_dir]))]

gleam_build = rule(
    implementation = _gleam_build_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".gleam"]),
        "deps": attr.label_list(allow_files = True),
        "gleam_toml": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
    },
)
