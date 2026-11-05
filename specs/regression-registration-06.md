# Specification

## Goal
Create a user registration feature where email addresses are unique across all accounts by default, but allow multiple accounts to share the same email address under certain conditions.

## Context
None provided.

## Functional Requirements

### FR-001
**Source:** USER  
Users can register an account using an email address and password.

### FR-002
**Source:** USER  
The system must allow multiple accounts to share the same email address under specific conditions (to be defined).

## Non-Functional Requirements
None identified at this stage.

## Acceptance Criteria

### AC-001
**Source:** USER  
Registration is successful when a user provides an email and password, with the email being unique across all accounts by default.

### AC-002
**Source:** USER  
The system allows multiple registrations with the same email address under specific conditions (to be defined).

## Edge Cases

1. **Duplicate Email Handling**: When attempting to register with an email that is already in use, the system must either:
   - Reject the registration if uniqueness is required.
   - Allow the registration if sharing is permitted under the defined conditions.

2. **Shared Email Addresses**: Ensure that multiple accounts sharing the same email address do not interfere with each other's account functionality (e.g., login, password recovery).

## Dependencies

1. The system must have a mechanism to define and check the conditions under which email addresses can be shared.
2. The database schema must support storing email addresses that may or may not be unique based on the defined conditions.

## Open Questions

1. **Conditions for Shared Emails**: What are the specific conditions under which multiple accounts can share the same email address? (e.g., organizational roles, account types, etc.)
2. **Uniqueness Enforcement**: How will the system enforce email uniqueness when it is required?
3. **User Experience for Shared Emails**: What user interface elements or notifications are needed to inform users about shared email addresses during registration?

## Assumptions

1. The conditions under which emails can be shared will be defined and integrated into the system.
2. The database schema will be modified to support non-unique email addresses when required.

# Completion Checklist
- [X] Goal preserved
- [X] No invented requirements
- [X] Sources identified for all requirements
- [X] Acceptance criteria are observable
- [X] Open questions are material and unresolved
- [X] Technical decisions deferred appropriately
- [X] Scope proportional to feature complexity

Please provide clarification on the open questions so that a complete specification can be finalized.