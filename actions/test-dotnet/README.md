# test-dotnet

Checks out the repository, restores .NET dependencies, runs the configured test command, and publishes TRX test results.

Main inputs:
- `dotnet_version`: .NET SDK version to install
- `restore_command`: restore command
- `test_command`: test command
