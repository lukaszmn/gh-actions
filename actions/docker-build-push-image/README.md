# docker-build-push-image

Generates Docker metadata tags and builds and pushes an image with optional build arguments and Dockerfile override.

Main inputs:
- `image`: full image name
- `context`: Docker build context
- `dockerfile`: optional Dockerfile path
