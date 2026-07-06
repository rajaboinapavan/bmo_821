# BMO 145 - ISO Checks Enhancement
## Codex / Developer Context

> **Purpose**
>
> This document provides the technical and business context required to understand the project before making any code changes.
>
> This project is **NOT** a greenfield implementation.
>
> It is an enhancement of an existing production-ready BMO ISO Checks application.

---

# 1. Project Overview

This application processes BMO ISO20022 PAIN.001 payment files and produces printable check packages.

The system already performs:

- Receive PAIN001 XML
- Validate XML
- Convert PAIN001 → Publisher Online XML
- Retrieve customer configuration from Encompass
- Duplicate check validation
- Generate Publisher Online XML
- Document Composition
- Generate GPD
- Generate PDFs
- Generate Positive Pay
- Generate Reports
- Generate PAIN002 acknowledgement
- ZIP client deliverables
- Upload production files

This processing pipeline is already implemented.

The objective of this project is **to enhance the existing implementation** for a new customer layout (Pilgrim's Pride).

---

# 2. Existing Processing Architecture

```
                     PAIN001 XML
                          │
                          ▼
             ConverterPreProcessor
                          │
                          ▼
                 XML Validation
                          │
                          ▼
            ConverterBusinessRules
                          │
                          ▼
          Encompass Configuration
                          │
                          ▼
               Publisher Online XML
                          │
                          ▼
           Duplicate Check Processing
                          │
                          ▼
             Document Composition
                          │
                          ▼
                Content Segments
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
      Check           Address        Remittance
        │
        ▼
             GPD Generation
                          │
                          ▼
                PDF Generation
                          │
                          ▼
              Positive Pay Files
                          │
                          ▼
               Client Deliverables
                          │
                          ▼
                   PAIN002 ACK
```

---

# 3. Existing AutoProcesses

The implementation uses two AutoProcesses.

---

## AutoProcess 1

Purpose:

Convert incoming PAIN001 XML into Publisher Online XML.

Responsibilities:

- XML Validation
- Business Rules
- Encompass Lookup
- Duplicate Check
- PO XML Generation
- Reports
- PAIN002

---

## AutoProcess 2

Purpose:

Document Composition

Responsibilities:

- GAML download
- Signature retrieval
- Graphics
- Check rendering
- Remittance rendering
- GPD generation
- PDF generation
- Positive Pay
- ZIP generation
- Aardvark upload

---

# 4. Existing Output

The repository contains sample output PDFs.

These represent the CURRENT production implementation.

The current document contains:

✓ Check

✓ Standard remittance

✓ Invoice table

Columns:

- Invoice Date
- Invoice Number
- Invoice Amount
- Discount Amount
- Invoice Net Amount

Information section contains

- Vendor
- Date
- Check Number

This output is considered the baseline implementation.

---

# 5. New Requirement

The customer supplied a new mockup.

The mockup is **NOT** a completely different document.

The check itself remains largely unchanged.

The majority of the changes are in the remittance section.

---

# 6. Main Business Change

Current document

```
Invoice Date
Invoice Number
Invoice Amount
Discount
Net Amount
```

New document

```
PO/Line

Ticket Date

Contract Price

Quantity (Bushels)

Gross Amount

Moisture

Test Weight

Damage

Foreign Material

Discounts

Fees

Net Amount
```

This new remittance is known as

"PILGRIM'S PRIDE TRUCK DELIVERY SETTLEMENT SHEET"

---

# 7. New Information Section

Current implementation

```
Vendor

Date

Check Number
```

New implementation

```
Vendor Number

Vendor Name

Material

Payment Document

Date

Check Number
```

Additional fields will need to be mapped into Publisher Online XML.

---

# 8. Multi-page Remittance

The existing implementation typically renders a simple invoice table.

The new requirement supports:

- Multiple pages
- Continuation pages
- Header repetition
- Totals on final page only

Example

```
Page 1

Settlement Table

Continued →

-----------------------

Page 2

Settlement Sheet (continued)

Remaining rows

Totals
```

---

# 9. Totals

New totals required

- Quantity
- Gross Amount
- Discounts
- Net Amount

Totals should appear only on the final page.

---

# 10. Existing Modules

The following modules already exist.

## Converter

Converter.pm

Purpose

PAIN001 → Publisher Online XML

---

## Business Rules

ConverterBusinessRules.pm

Purpose

Business mapping

Encompass lookup

XML mapping

Business logic

---

## Duplicate Check

DupCheckPreProcessor.pm

DupCheck_Utils.pm

Purpose

Duplicate validation

---

## Document Composition

DocCompPreProcessor.pm

DocCompPostProcessor.pm

Purpose

Rendering pipeline

---

## Content Segments

Address.pm

Check.pm

Logo.pm

Check_Logo.pm

PageNumbering.pm

BMO_ISO_Remit_Table.pm

BMO_ISO_Remit_Table_7cols.pm

---

## Utilities

ISO_Utils.pm

DBHelper.pm

---

# 11. Expected Code Changes

Primary areas likely requiring changes

✓ ConverterBusinessRules.pm

- Add new XML mappings
- Populate new settlement fields

---

✓ BMO_ISO_Remit_Table_7cols.pm

Primary implementation target.

Expected responsibilities

- Render settlement table
- Pagination
- Totals
- Continuation

---

Possible minor changes

Check.pm

Address.pm

Only if required by the mockup.

---

# 12. Areas That Should NOT Be Rewritten

The following implementation already works.

Avoid unnecessary refactoring.

DO NOT rewrite

✓ Converter pipeline

✓ AutoProcess

✓ run.pl

✓ XML Validation

✓ Duplicate Check

✓ Encompass Integration

✓ GPD generation

✓ PDF generation

✓ Positive Pay

✓ PAIN002

✓ ZIP generation

✓ Existing Reports

Prefer extending existing functionality.

---

# 13. Existing vs New

Existing

Simple vendor remittance

↓

New

Pilgrim settlement sheet

--------------------------------

Existing

Invoice table

↓

New

Agricultural settlement table

--------------------------------

Existing

Single page

↓

New

Continuation pages

--------------------------------

Existing

Basic information

↓

New

Expanded information block

--------------------------------

Existing

No settlement totals

↓

New

Settlement totals

---

# 14. Development Strategy

Before modifying code

1.

Understand existing implementation.

2.

Compare existing output PDF.

3.

Compare new mockup.

4.

Reuse existing modules.

5.

Modify only where necessary.

6.

Avoid changing stable processing pipeline.

---

# 15. Goal

This project is an enhancement—not a rewrite.

Reuse the existing architecture.

Implement only the business changes required by the new Pilgrim's Pride mockup while preserving all existing production functionality.