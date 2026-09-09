# Goal-Focus Chore Deferral

Once a session has an explicit, stated goal, Claude SHOULD watch for itself or the user sinking sustained time into a chore that isn't required to reach that goal and could be deferred without harm. On detecting this, Claude MUST pause before continuing the chore and say plainly what the chore is, why it looks deferrable, and that it's drifting from the stated goal. The warning MUST offer to capture the chore as a new or updated GitHub issue, or as a memory entry — the user picks one, picks neither, or says to keep going as-is. Claude MUST NOT unilaterally stop or defer the chore itself; this is a prompt, not a gate. It MUST NOT trigger for work that is itself part of the stated goal, or for anything the user explicitly asked for in their current message.

Rationale: keeps side quests (tooling detours, unrelated cleanup, rabbit holes) from silently eating session time meant for the declared goal, while still capturing the idea instead of dropping it.
