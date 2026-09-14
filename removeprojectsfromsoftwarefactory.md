  # Remove projects from Software Factory

  ## Summary

  Add a trashcan button to every project card, including unavailable projects and the dashboard’s host project. Removal affects
  only that dashboard’s project list. Project files, installed skills, specifications, history, and running work remain intact.

  Removed projects stay hidden across refreshes and restarts until explicitly registered again.

  ## Interface

  - Place a small trashcan button at the card’s top right. Use an inline SVG and accessible label, “Remove {project name}”.
  - Refactor the card into a container with separate navigation and removal controls. Avoid nested buttons. Removal must remain
    available when project navigation is disabled.

  - Open a confirmation dialog titled “Remove {project name}?” with the message “This removes the project from this dashboard.
    Its files, Software Factory installation, and history will be kept.”

  - Provide Cancel and Remove buttons. Support keyboard navigation, Escape, focus containment, and focus restoration.
  - Disable repeated submission while removing. On success, close the dialog, refresh the list immediately, and announce
    “{project name} was removed.” On failure, keep the card and display an error with retry available.

  ## Registration and persistence

  - Add DELETE /api/projects/{project_id}. Require the same origin and write token used by Add project, with no request body.
    Return 204 on success or repeated removal, 404 for an unknown project, and explicit permission or registry-conflict errors.

  - Keep removal available without a configured projects directory. It requires write access only to the dashboard registry.
  - Persist removed project IDs in removed-projects.json beside the existing registry. Use the existing registry lock and atomic
    JSON writer. Retain underlying registration metadata; the removal list determines whether a project is registered for
    display and access.

  - Apply removal filtering after combining saved registrations, Docker configuration, and automatic host discovery. Removed
    projects must also become inaccessible through dashboard detail endpoints.

  - Successful Add project and explicit launcher --project registration clear the removal marker. Ordinary startup and implicit
    host registration must preserve it. Re-adding retains the existing project identity and history.

  - Mount the dashboard registry writable in launcher-managed Docker even without a projects directory. Continue mounting
    project factories read-only. Compose and native mode must use the same removal rules.

  - Mirror implementation and documentation in both model packages. Document removal, persistence, and restoration.

  ## Validation
    without navigating into the card.

  - Backend tests cover authentication, repeated removal, unavailable projects, host removal, registry locking, and rejected
    access to removed project details.

  - Verify removal survives native, Docker, and Compose restarts, including stale Docker configuration and automatic host
    discovery.

  - Verify explicit re-registration restores the same identity and history. Confirm removal leaves project files unchanged and
    does not affect another dashboard’s registry.

  - Run frontend tests and build, backend checks, installer checks, and model parity checks. Report existing unrelated factory-
    check failures without repairing missing workflow modules.