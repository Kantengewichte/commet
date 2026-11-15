#!/bin/bash
set -euo pipefail

PROJECT_PATH="$(git rev-parse --show-toplevel)/commet/"
PATH="$PROJECT_PATH/../.fvm/flutter_sdk/bin/:$PATH"
ORG_GRADLE_PROJECT_disable-abi-filtering=true


export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_SDK_ROOT=$HOME/Android/Sdk

cd $PROJECT_PATH
dart run scripts/codegen.dart

cd $PROJECT_PATH
flutter run --dart-define BUILD_MODE=debug --dart-define PLATFORM=android
