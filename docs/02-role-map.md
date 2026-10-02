# Role Map — Potomac Defense Systems

> **Summary:** Defines what access each job gets automatically on day one, which program data needs extra checks before it is granted, which role combinations are never allowed, and how exceptions are handled.

> **About this lab:** Potomac Defense Systems is a fictional defense and space contractor I created for my IAM portfolio. Every person, account, program and piece of data is made up, and nothing is classified.

## 1. Two Kinds of Access

```text
Birthright access    → granted on day one, based on job role
Conditional access   → granted only when conditions are met
```

| Type        | Based on                          | Example                     |
| ----------- | --------------------------------- | --------------------------- |
| Birthright  | Department / job role             | Email, VPN, engineering tools |
| Conditional | Program assignment + checks       | Radar CUI file share        |

Job title gives birthright access. Program data needs an assignment, training and approval, because CUI is need-to-know.

## 2. Birthright Access by Role

Every account gets `GG-Role-AllStaff` (email, VPN, intranet, timesheets).

| Role group                  | Who                    | Day-one access                             |
| --------------------------- | ---------------------- | ------------------------------------------ |
| `GG-Role-Engineers`         | Engineers              | Engineering tools, engineering share (read) |
| `GG-Role-ProgramManagers`   | Program managers       | Project tracking, approve program access   |
| `GG-Role-Finance`           | Finance                | **Approve invoices** for payment           |
| `GG-Role-AccountsPayable`   | Accounts Payable       | **Create vendors**, enter invoices         |
| `GG-Role-HR`                | Human Resources        | HR system, personnel files                 |
| `GG-Role-Contracts`         | Contracts              | Contract files, government customer portal |
| `GG-Role-Helpdesk`          | Helpdesk               | Ticketing system                           |
| `GG-Role-Security`          | Security team          | Security logs (read)                       |
| `GG-Role-Subcontractors`    | Subcontractors         | Email, VPN only. No company shares         |

**Admin rights never come from a role group.** Helpdesk staff use a separate `t2-` account for password resets (see `01-directory-design.md`).

## 3. Conditional Program Access

Programs: **Radar** (radar sensors), **Satellite** (satellite ground systems), **Shipboard** (shipboard combat software).

```text
Engineer assigned to Radar
        ↓
All checks pass
        ↓
GG-Role-Radar-Engineers
        ↓
DL-Share-Radar-CUI-Modify
        ↓
Radar CUI File Share
```

### Checks before granting program data

| Check                                 | Why                                              |
| ------------------------------------- | ------------------------------------------------ |
| `Program = Radar` set by HR or the PM | Need-to-know: assigned to the program, not the job |
| CUI training completed                | NIST 800-171 requires training before handling CUI |
| `US Person = Yes` (export-controlled) | Export law                                       |
| Program manager approves              | The data owner decides who sees the data         |

If any check fails, the account gets birthright access only. When the program attribute changes or is removed, program access is removed automatically.

## 4. Separation of Duties

No single person should be able to complete a risky process from start to finish.

| Role A                    | Role B                    | Risk                                                |
| ------------------------- | ------------------------- | --------------------------------------------------- |
| `GG-Role-AccountsPayable` | `GG-Role-Finance`         | Create a fake vendor, then approve its invoice      |

```text
Create vendor (AP) → Submit invoice → Approve invoice (Finance) → Payment
                     ↑ same person = fraud with no one else involved
```

The JML engine checks every change. If a user would end up in both groups, it **denies the change and raises an alert**.

## 5. Exceptions

Sometimes the business needs a temporary exception, such as covering for a coworker on leave.

| Element               | Rule                                                        |
| --------------------- | ----------------------------------------------------------- |
| Request               | Manager requests it with a business reason                  |
| Approval              | Someone outside the conflict approves (e.g. CFO)            |
| Time limit            | Maximum 14 days, then removed automatically                 |
| Compensating control  | Cannot approve invoices from vendors they created; Finance lead reviews all approvals |
| Record                | Logged as an exception for audit                            |

Preferred first: have someone else in the role cover the work, so no exception is needed.

## 6. Why I Made These Choices

| Choice | Why |
| --- | --- |
| Birthright and conditional access are separate | Being an engineer doesn't mean needing every program's data |
| Program access comes from an attribute, not an OU | Engineers move between programs; changing an attribute is simpler and automatic |
| CUI training is a check before access | Users must be trained before handling CUI |
| SoD denies by default | Prevents fraud even when every individual permission looks legitimate |
| Exceptions are time-limited with compensating controls | Blocking the business pushes people toward workarounds like shared passwords |

## 7. Lab Notes

* **CUI training:** stored as an account attribute in the lab. In production it would come from the training system.
* **Approvals:** simulated by a field in the HR roster CSV. In production they would come from a ticketing or governance tool.
* **One program per person:** the lab assigns each engineer to one program to keep the roster simple.
