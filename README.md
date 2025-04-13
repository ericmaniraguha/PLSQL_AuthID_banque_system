# Banking Application with PL/SQL AUTHID-Based Security

This repository demonstrates how to implement role-based access control (RBAC) in a banking application using Oracle PL/SQL's AUTHID clause. The solution shows how to leverage both definer rights and invoker rights to create a secure multi-role banking system.

## Overview

This project implements a banking application with three distinct roles:
- **Tellers** - Can create customers and process regular transactions
- **Managers** - Can approve high-value transactions and update customer information
- **Auditors** - Can view data but not modify anything

The application uses PL/SQL packages with different AUTHID contexts to enforce security at the database level.

## Database Design

### Tables
- `customers` - Stores basic customer information
- `accounts` - Contains account balances and links to customers
- `transactions` - Records all financial transactions with approval status
- `audit_logs` - Maintains a comprehensive security audit trail

### PL/SQL Packages

The architecture uses two types of packages:

#### 1. AUTHID DEFINER Packages
- `audit_pkg` - Runs with package owner privileges regardless of the caller
- Ensures all users can write audit logs without direct table privileges
- Provides controlled access to audit information

#### 2. AUTHID CURRENT_USER Packages
- `customer_mgmt_pkg` - Manages customer operations (create, read, update)
- `transaction_pkg` - Handles financial transactions (create, approve, view)
- Operations execute with the caller's privileges, enforcing role-based restrictions

## Security Implementation

### Role-Based Security

The system uses a layered security approach:
1. **Database roles** (`bank_teller`, `bank_manager`, `bank_auditor`)
2. **AUTHID contexts** (DEFINER vs CURRENT_USER) 
3. **Runtime role verification** (using `has_role()` function)
4. **Comprehensive audit logging**

### Fine-Grained Access Control

To implement procedure-level access control within packages, the system uses:

1. **Role-check function**: Internal checks verify if the caller has appropriate roles
2. **Privilege-based execution**: Operations automatically fail if the caller lacks required privileges

## Installation & Setup

1. Run the table creation scripts
2. Create object types and sequences
3. Create the roles
4. Create the packages
5. Grant appropriate privileges to roles
6. Create users and assign roles

## Usage Examples

### Teller Operations
```sql
-- Create a customer
DECLARE
  v_customer_id NUMBER;
BEGIN
  customer_mgmt_pkg.create_customer(
    'John Smith', '123 Main St', '555-1234', 'john@example.com', v_customer_id
  );
  DBMS_OUTPUT.PUT_LINE('Created customer ID: ' || v_customer_id);
END;
/

-- Create a transaction
DECLARE
  v_transaction_id NUMBER;
BEGIN
  transaction_pkg.create_transaction(
    1001, 500, 'DEPOSIT', 'Initial deposit', v_transaction_id
  );
  DBMS_OUTPUT.PUT_LINE('Created transaction ID: ' || v_transaction_id);
END;
/
```

### Manager Operations
```sql
-- Approve a high-value transaction
BEGIN
  transaction_pkg.approve_transaction(5001);
  DBMS_OUTPUT.PUT_LINE('Transaction approved');
END;
/

-- Update customer information
BEGIN
  customer_mgmt_pkg.update_customer(
    1001, p_phone => '555-5678', p_email => 'john.smith@example.com'
  );
  DBMS_OUTPUT.PUT_LINE('Customer updated');
END;
/
```

### Auditor Operations
```sql
-- View transaction details
DECLARE
  v_transaction transaction_details_rec;
BEGIN
  v_transaction := transaction_pkg.get_transaction_details(5001);
  DBMS_OUTPUT.PUT_LINE('Transaction: ' || v_transaction.transaction_id);
  DBMS_OUTPUT.PUT_LINE('Amount: $' || v_transaction.amount);
  DBMS_OUTPUT.PUT_LINE('Status: ' || v_transaction.status);
END;
/

-- View audit logs
BEGIN
  audit_pkg.view_audit_logs(
    SYSDATE-7, SYSDATE  -- Last 7 days
  );
END;
/
```

## Known Issues & Limitations

### Granting Privileges on Package Components

Oracle doesn't support granting privileges on individual package components. If you need this level of access control, you'll need to use one of these approaches:

1. **Split the packages by functionality**:
   - Create separate packages for different security levels
   - Grant execute privileges on entire packages

2. **Use runtime role checks**:
   - Grant execute on entire packages
   - Implement explicit role checks in each procedure

### Code Example for Separate Packages

```sql
-- Create read-only packages for auditors
CREATE OR REPLACE PACKAGE transaction_read_pkg 
AUTHID CURRENT_USER AS
    -- Only include read-only functions
    FUNCTION get_transaction_details(
        p_transaction_id IN NUMBER
    ) RETURN transaction_details_rec;
END transaction_read_pkg;
/

-- Grant to auditor role
GRANT EXECUTE ON transaction_read_pkg TO bank_auditor;
```

## Contributors

This project was created as a demonstration of Oracle's AUTHID-based security mechanisms for role-based access control in enterprise applications.

## MIT License

Copyright (c) 2025 Eric Maniraguha

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
