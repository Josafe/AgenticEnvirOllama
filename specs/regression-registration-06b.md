### Specification Agent Output

```markdown
# Specification

## Goal
Create a user registration feature where email addresses must be unique across all accounts, while also allowing multiple accounts to share the same email address.

## Context
None provided beyond the request.

## Functional Requirements

### FR-001
**Source:** USER  
Users can register using an email address and password.

### FR-002
**Source:** USER  
Email addresses must be unique across all accounts.

### FR-003
**Source:** USER  
The system must allow multiple accounts to share the same email address.

## Non-Functional Requirements
None identified at this stage.

## Acceptance Criteria

### AC-001
**Source:** USER  
New user registrations are successful when using unique email addresses.

### AC-002
**Source:** USER  
Registration fails if an email address is already registered under another account, except when multiple accounts share the same email.

## Edge Cases

### EC-001
**Description:** Attempting to register with an email that is already in use by a single account.
**Required Behavior:** Registration should fail unless the system explicitly allows multiple accounts to share the same email.

### EC-002
**Description:** Multiple accounts sharing the same email address.
**Required Behavior:** The system must support this scenario as per user requirements, though the exact implementation details are not specified.

## Dependencies
None identified at this stage.

## Open Questions

### OQ-001
The request contains conflicting requirements:
1. Email addresses must be unique across all accounts.
2. Multiple accounts can share the same email address.

Please clarify which of these requirements should take precedence or if there is a specific condition under which each applies (e.g., different account types, services, or contexts where sharing is allowed).

## Assumptions
None identified at this stage.

## Completion Checklist

- [X] Goal preserves user intent.
- [X] No invented requirements attributed to the user.
- [X] All requirements have a source.
- [X] Acceptance criteria describe observable outcomes.
- [X] Open questions are limited to material unresolved decisions.
- [X] Technical decisions deferred unless explicitly requested.
- [X] Level of detail proportional to feature complexity.
- [X] All required sections present.

```