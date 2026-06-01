# syntax=docker/dockerfile:1
# Build context = ./backend (see deploy/docker-compose.yml). Restores via backend/NuGet.config (nuget.org only).

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore Lumen.slnx
RUN dotnet publish src/Lumen.Api/Lumen.Api.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Lumen.Api.dll"]
