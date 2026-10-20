FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY app/WeeklyReports.Intranet/WeeklyReports.Intranet.csproj app/WeeklyReports.Intranet/
RUN dotnet restore app/WeeklyReports.Intranet/WeeklyReports.Intranet.csproj

COPY app/WeeklyReports.Intranet/ app/WeeklyReports.Intranet/
RUN dotnet publish app/WeeklyReports.Intranet/WeeklyReports.Intranet.csproj \
    --configuration Release \
    --no-restore \
    --output /out

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_HTTP_PORTS=8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    Reports__Root=reports

COPY --from=build --chown=app:app /out/ ./
RUN mkdir -p /app/reports /home/app/.aspnet/DataProtection-Keys \
    && chown -R app:app /app/reports /home/app/.aspnet

USER app
EXPOSE 8080
VOLUME ["/app/reports"]

ENTRYPOINT ["dotnet", "WeeklyReports.Intranet.dll"]
