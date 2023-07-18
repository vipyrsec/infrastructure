-- Script to bootstrap the database with necessary roles and users

-- Dragonfly
-- Create the database
CREATE DATABASE dragonfly OWNER dragonfly;
-- Create an admin role
CREATE ROLE dragonfly_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dragonfly_admin;
-- Create a read-only role
CREATE ROLE dragonfly_read;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dragonfly_read;
-- Create initial user roles
CREATE ROLE bradley WITH PASSWORD 'shadow' IN ROLE dragonfly_admin LOGIN;
CREATE ROLE robin WITH PASSWORD 'shadow' IN ROLE dragonfly_read LOGIN;
