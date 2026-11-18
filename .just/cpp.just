# The C, C++, and Objective-C checks. SwiftPM and Xcode build and test the C++ targets, so these
# recipes format and lint them. Project recipes go in project.just.

set shell := ["bash", "-euo", "pipefail", "-c"]
set working-directory := ".."

llvm := `if command -v brew >/dev/null && [[ -d "$(brew --prefix llvm 2>/dev/null)" ]]; then echo "$(brew --prefix llvm)/bin/"; fi`
env := "Scripts/with-env.sh"

# Install LLVM, for clang-format and clang-tidy, and xmake when a project uses it.
setup:
    if [[ ! -x "{{ llvm }}clang-tidy" ]] && ! command -v clang-tidy >/dev/null; then brew install llvm; fi
    if [[ -n "$(git ls-files --cached --others --exclude-standard -- xmake.lua '*/xmake.lua')" ]] && ! command -v xmake >/dev/null; then brew install xmake; fi

# Format the C and C++ code.
format:
    just cpp::files | xargs -0 -r {{ llvm }}clang-format -i

# Fail if the C and C++ code is not formatted.
format-check:
    just cpp::files | xargs -0 -r {{ llvm }}clang-format --dry-run --Werror

# SwiftPM type-checks the C++ targets with the Swift ones.
typecheck:

# Run clang-tidy over each translation unit SwiftPM or xmake builds, with its flags.
lint:
    {{ env }} python3 Scripts/Quality/compile_commands.py
    {{ llvm }}run-clang-tidy -quiet -p . -clang-tidy-binary {{ llvm }}clang-tidy -clang-apply-replacements-binary {{ llvm }}clang-apply-replacements

# Apply the clang-tidy fixes it can, then format; `just lint` reports the rest.
lint-fix:
    {{ env }} python3 Scripts/Quality/compile_commands.py
    -{{ llvm }}run-clang-tidy -quiet -p . -clang-tidy-binary {{ llvm }}clang-tidy -clang-apply-replacements-binary {{ llvm }}clang-apply-replacements -fix
    just cpp::format

# SwiftPM runs the tests that cover the C++ targets.
test:

# The Swift guard covers the C++ targets.
guard:

# Run every C++ check CI runs.
verify: format-check lint

# The C++ checks the pre-commit hook runs.
pre-commit: format-check

[private]
files:
    git ls-files -z --cached --others --exclude-standard -- '*.c' '*.cc' '*.cpp' '*.cxx' '*.h' '*.hh' '*.hpp' '*.hxx' '*.m' '*.mm'
