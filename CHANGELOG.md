# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Auth & sync API (`backend/`, #8): email/password registration with emailed 6-digit verification, login with lockout, Sign in with Apple, rotating refresh tokens with replay detection, forgot/reset & change password, logout / logout all devices, account deletion, data export, profile + workout-log sync, per-IP rate limiting.
- API Docker image, CI (typecheck, tests, image build), staging auto-deploy and manual "Promote to production" (same image) workflows.
- Repository bootstrap (README, CHANGELOG, .gitignore).
