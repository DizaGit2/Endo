-- P0a Postgres init: runs once on first container start (as superuser).
-- Creates the Keycloak role + database and the Lumen database with required extensions.

CREATE USER keycloak WITH PASSWORD 'keycloak';
CREATE DATABASE keycloak OWNER keycloak;

CREATE DATABASE lumen;

\connect lumen
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
