set shell := ["zsh", "-eu", "-o", "pipefail", "-c"]

project := "Maccy.xcodeproj"
scheme := "Maccy"
destination := "platform=macOS"
derived_data := ".build/DerivedData"
app := derived_data + "/Build/Products/Debug/Maccy.app"
signing := "CODE_SIGNING_ALLOWED=NO"

# Show available recipes.
default:
  @just --list

# Build the app locally without requiring a signing identity.
build:
  xcodebuild build \
    -project {{project}} \
    -scheme {{scheme}} \
    -destination '{{destination}}' \
    -derivedDataPath {{derived_data}} \
    {{signing}}

# Stop any running Maccy instance.
kill:
  @pkill -x Maccy 2>/dev/null || true

# Build and launch the app.
run: kill build
  open -n {{app}}

# Launch the last built app without rebuilding.
run-built: kill
  @test -d {{app}} || (echo "Missing {{app}}. Run 'just build' first." >&2; exit 1)
  open -n {{app}}

# Build, launch, and verify the process is running.
verify: run
  @sleep 1
  pgrep -x Maccy >/dev/null

# Stream Maccy logs from the unified logging system.
logs:
  log stream --info --predicate 'process == "Maccy"'

# Run the full test plan. This includes UI tests and may require a foreground desktop session.
test:
  xcodebuild test \
    -project {{project}} \
    -scheme {{scheme}} \
    -testPlan Maccy \
    -destination '{{destination}}' \
    -derivedDataPath {{derived_data}} \
    {{signing}}

# Run unit tests only.
test-unit:
  xcodebuild test \
    -project {{project}} \
    -scheme {{scheme}} \
    -testPlan Maccy \
    -destination '{{destination}}' \
    -derivedDataPath {{derived_data}} \
    -only-testing:MaccyTests \
    {{signing}}

# Run UI tests only.
test-ui:
  xcodebuild test \
    -project {{project}} \
    -scheme {{scheme}} \
    -testPlan Maccy \
    -destination '{{destination}}' \
    -derivedDataPath {{derived_data}} \
    -only-testing:MaccyUITests \
    {{signing}}

# Run paste bar focused unit tests.
test-pastebar:
  xcodebuild test \
    -project {{project}} \
    -scheme {{scheme}} \
    -testPlan Maccy \
    -destination '{{destination}}' \
    -derivedDataPath {{derived_data}} \
    -only-testing:MaccyTests/PasteBarDisplayKindTests \
    -only-testing:MaccyTests/PasteBarResultProviderTests \
    -only-testing:MaccyTests/PasteBarActionDispatcherTests \
    {{signing}}

# Run the default lint suite.
lint: lint-swift

# Lint Swift source.
lint-swift:
  swiftlint lint --quiet

# Lint localized strings with BartyCrouch.
lint-strings:
  @command -v bartycrouch >/dev/null || (echo "bartycrouch is not installed." >&2; exit 127)
  bartycrouch lint

# Find unused code with Periphery.
lint-unused:
  @command -v periphery >/dev/null || (echo "periphery is not installed." >&2; exit 127)
  periphery scan

# Run build, Swift lint, and unit tests.
check: lint build test-unit

# Remove local build output.
clean:
  rm -rf {{derived_data}}
