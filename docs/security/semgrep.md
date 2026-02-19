# Semgrep Security Scanning

## Overview

Semgrep is a static analysis tool that runs on every pull request to detect security vulnerabilities, hardcoded secrets, and unsafe coding patterns before they reach production.

## How It Works

1. **On every PR**: Semgrep scans changed files using diff-aware scanning
2. **Findings are reported**: Results appear as a PR comment
3. **High severity blocks merge**: PRs with high-severity findings cannot be merged
4. **Medium/Low are warnings**: These don't block but should be addressed

## Rulesets

### Kotlin/Java

| Ruleset | Purpose |
|---------|---------|
| `p/security-audit` | General security vulnerabilities |
| `p/kotlin` | Kotlin-specific security issues |
| `p/java` | Java-specific security issues |
| `r/kotlin.lang.security` | Kotlin security patterns |
| `r/java.lang.security` | Java security patterns |
| `p/secrets` | Hardcoded secrets detection |
| `p/github-actions` | Shell injection in workflows |
| `p/docker` | Dockerfile security |

### PHP

| Ruleset | Purpose |
|---------|---------|
| `p/security-audit` | General security vulnerabilities |
| `p/php` | PHP-specific security issues |
| `r/php.lang.security` | PHP security patterns |
| `p/secrets` | Hardcoded secrets detection |
| `p/github-actions` | Shell injection in workflows |
| `p/docker` | Dockerfile security |

## Common Findings and Fixes

### 1. SQL Injection (HIGH)

**Problem**: User input concatenated into SQL queries.

```kotlin
// VULNERABLE
val query = "SELECT * FROM users WHERE id = $userId"
jdbcTemplate.query(query)
```

**Fix**: Use parameterized queries.

```kotlin
// SAFE
jdbcTemplate.query("SELECT * FROM users WHERE id = ?", userId)
```

### 2. Command Injection (HIGH)

**Problem**: User input passed to system commands.

```kotlin
// VULNERABLE
Runtime.getRuntime().exec("ls $userInput")
```

**Fix**: Avoid shell execution or sanitize input.

```kotlin
// SAFE - use ProcessBuilder with argument array
ProcessBuilder(listOf("ls", "-la", safeDirectory)).start()
```

### 3. Hardcoded Secrets (HIGH)

**Problem**: API keys or passwords in source code.

```kotlin
// VULNERABLE
val apiKey = "sk_live_abc123xyz789..."
```

**Fix**: Use environment variables or secrets management.

```kotlin
// SAFE
val apiKey = System.getenv("API_KEY")
```

### 4. Shell Injection in GitHub Actions (HIGH)

**Problem**: User-controlled input in workflow `run:` steps.

```yaml
# VULNERABLE
- run: echo "${{ github.event.pull_request.title }}"
```

**Fix**: Use environment variables or intermediate steps.

```yaml
# SAFE
- run: echo "$TITLE"
  env:
    TITLE: ${{ github.event.pull_request.title }}
```

### 5. Weak Cryptographic Algorithms (MEDIUM)

**Problem**: Using MD5, SHA1, or ECB mode.

```kotlin
// VULNERABLE
MessageDigest.getInstance("MD5")
MessageDigest.getInstance("SHA-1")
Cipher.getInstance("AES/ECB/PKCS5Padding")
```

**Fix**: Use strong algorithms.

```kotlin
// SAFE
MessageDigest.getInstance("SHA-256")
Cipher.getInstance("AES/GCM/NoPadding")
```

### 6. Insecure Deserialization (HIGH)

**Problem**: Deserializing untrusted data.

```kotlin
// VULNERABLE
ObjectInputStream(inputStream).readObject()
```

**Fix**: Use safe serialization formats like JSON.

```kotlin
// SAFE
objectMapper.readValue(jsonString, MyClass::class.java)
```

### 7. Path Traversal (MEDIUM)

**Problem**: User input used in file paths.

```kotlin
// VULNERABLE
File("/uploads/$filename").readText()
```

**Fix**: Validate and sanitize file paths.

```kotlin
// SAFE
val safePath = Paths.get("/uploads").resolve(filename).normalize()
if (!safePath.startsWith("/uploads")) {
    throw SecurityException("Invalid path")
}
safePath.toFile().readText()
```

## Running Locally

### Installation

```bash
# macOS
brew install semgrep

# pip
pip install semgrep

# Docker
docker pull semgrep/semgrep
```

### Run a Scan

```bash
# Kotlin project - full scan
semgrep scan --config p/security-audit --config p/kotlin --config p/java

# PHP project - full scan
semgrep scan --config p/security-audit --config p/php

# Scan specific file
semgrep scan --config p/kotlin src/main/kotlin/MyService.kt

# Scan with JSON output
semgrep scan --config p/kotlin --json > results.json

# Quick scan with auto-detected rules
semgrep scan --config auto
```

## Ignoring False Positives

### Inline Ignore

```kotlin
// nosemgrep: kotlin.lang.security.some-rule
val data = someOperation()
```

```php
// nosemgrep: php.lang.security.some-rule
$data = someOperation();
```

### Configuration-Level Ignore

Create `.semgrep.yml` in your repo root:

```yaml
paths:
  exclude:
    - src/test/
    - legacy/
    - vendor/
```

## CI Behavior

| Severity | PR Comment | Blocks Merge |
|----------|------------|--------------|
| High | Yes | Yes |
| Medium | Yes (collapsed) | No |
| Low | Yes (collapsed) | No |

## Getting Help

- [Semgrep Documentation](https://semgrep.dev/docs/)
- [Rule Registry](https://semgrep.dev/r)
- [Writing Custom Rules](https://semgrep.dev/docs/writing-rules/overview/)
