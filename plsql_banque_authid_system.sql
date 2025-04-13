-- 1. Create necessary tables
CREATE TABLE customers (
    customer_id NUMBER PRIMARY KEY,
    customer_name VARCHAR2(100) NOT NULL,
    address VARCHAR2(200),
    phone_number VARCHAR2(20),
    email VARCHAR2(100),
    creation_date DATE DEFAULT SYSDATE,
    created_by VARCHAR2(30)
);

CREATE TABLE accounts (
    account_id NUMBER PRIMARY KEY,
    customer_id NUMBER NOT NULL,
    account_type VARCHAR2(20) NOT NULL,
    balance NUMBER(12,2) DEFAULT 0,
    status VARCHAR2(10) DEFAULT 'ACTIVE',
    creation_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE transactions (
    transaction_id NUMBER PRIMARY KEY,
    account_id NUMBER NOT NULL,
    amount NUMBER(12,2) NOT NULL,
    transaction_type VARCHAR2(20) NOT NULL,
    status VARCHAR2(20) DEFAULT 'PENDING',
    description VARCHAR2(200),
    created_by VARCHAR2(30),
    creation_date DATE DEFAULT SYSDATE,
    approved_by VARCHAR2(30),
    approval_date DATE,
    CONSTRAINT fk_account FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    CONSTRAINT chk_amount CHECK (amount > 0)
);

CREATE TABLE audit_logs (
    log_id NUMBER PRIMARY KEY,
    user_id VARCHAR2(30),
    action_type VARCHAR2(50),
    table_affected VARCHAR2(30),
    record_id NUMBER,
    old_value CLOB,
    new_value CLOB,
    action_date DATE DEFAULT SYSDATE,
    ip_address VARCHAR2(15)
);

-- Create sequences for IDs
CREATE SEQUENCE customer_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE account_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE transaction_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE log_id_seq START WITH 1 INCREMENT BY 1;

-- 2. Create Object Types for returning complex data
CREATE OR REPLACE TYPE transaction_details_rec AS OBJECT (
    transaction_id NUMBER,
    account_id NUMBER,
    customer_id NUMBER,
    customer_name VARCHAR2(100),
    amount NUMBER(12,2),
    transaction_type VARCHAR2(20),
    status VARCHAR2(20),
    created_by VARCHAR2(30),
    creation_date DATE,
    approved_by VARCHAR2(30),
    approval_date DATE
);
/

-- 3. Create roles for different bank employees
CREATE ROLE bank_teller;
CREATE ROLE bank_manager;
CREATE ROLE bank_auditor;

-- 4. Create DEFINER RIGHTS package for audit logging
-- This runs with package owner privileges regardless of caller
CREATE OR REPLACE PACKAGE audit_pkg
AUTHID DEFINER AS
    PROCEDURE log_activity(
        p_user_id IN VARCHAR2,
        p_action_type IN VARCHAR2,
        p_table_affected IN VARCHAR2,
        p_record_id IN NUMBER,
        p_old_value IN CLOB DEFAULT NULL,
        p_new_value IN CLOB DEFAULT NULL,
        p_ip_address IN VARCHAR2 DEFAULT NULL
    );
    
    PROCEDURE view_audit_logs(
        p_start_date IN DATE,
        p_end_date IN DATE DEFAULT SYSDATE,
        p_user_id IN VARCHAR2 DEFAULT NULL
    );
END audit_pkg;
/

CREATE OR REPLACE PACKAGE BODY audit_pkg AS
    PROCEDURE log_activity(
        p_user_id IN VARCHAR2,
        p_action_type IN VARCHAR2,
        p_table_affected IN VARCHAR2,
        p_record_id IN NUMBER,
        p_old_value IN CLOB DEFAULT NULL,
        p_new_value IN CLOB DEFAULT NULL,
        p_ip_address IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        -- Anyone can write to audit logs through this procedure
        -- even if they don't have direct INSERT privileges
        INSERT INTO audit_logs (
            log_id, user_id, action_type, table_affected, 
            record_id, old_value, new_value, action_date, ip_address
        ) VALUES (
            log_id_seq.NEXTVAL, p_user_id, p_action_type, p_table_affected,
            p_record_id, p_old_value, p_new_value, SYSDATE, p_ip_address
        );
        COMMIT;
    END log_activity;
    
    PROCEDURE view_audit_logs(
        p_start_date IN DATE,
        p_end_date IN DATE DEFAULT SYSDATE,
        p_user_id IN VARCHAR2 DEFAULT NULL
    ) IS
        CURSOR c_logs IS
            SELECT * FROM audit_logs
            WHERE action_date BETWEEN p_start_date AND p_end_date
            AND (p_user_id IS NULL OR user_id = p_user_id)
            ORDER BY action_date DESC;
        r_log c_logs%ROWTYPE;
    BEGIN
        -- This runs with package owner privileges
        -- Only those with EXECUTE on this procedure can view logs
        OPEN c_logs;
        LOOP
            FETCH c_logs INTO r_log;
            EXIT WHEN c_logs%NOTFOUND;
            DBMS_OUTPUT.PUT_LINE(
                TO_CHAR(r_log.action_date, 'YYYY-MM-DD HH24:MI:SS') || ' | ' ||
                RPAD(r_log.user_id, 15) || ' | ' ||
                RPAD(r_log.action_type, 15) || ' | ' ||
                RPAD(r_log.table_affected, 12) || ' | ' ||
                'ID: ' || r_log.record_id
            );
        END LOOP;
        CLOSE c_logs;
    END view_audit_logs;
END audit_pkg;
/

-- 5. Create INVOKER RIGHTS packages for customer management
-- This will respect the caller's privileges
CREATE OR REPLACE PACKAGE customer_mgmt_pkg
AUTHID CURRENT_USER AS
    -- Available to tellers - restricted by their role privileges
    PROCEDURE create_customer(
        p_name IN VARCHAR2,
        p_address IN VARCHAR2,
        p_phone IN VARCHAR2,
        p_email IN VARCHAR2,
        p_customer_id OUT NUMBER
    );
    
    -- Available to tellers and managers
    FUNCTION get_customer_details(
        p_customer_id IN NUMBER
    ) RETURN customers%ROWTYPE;
    
    -- Available only to managers due to UPDATE privilege requirement
    PROCEDURE update_customer(
        p_customer_id IN NUMBER,
        p_name IN VARCHAR2 DEFAULT NULL,
        p_address IN VARCHAR2 DEFAULT NULL,
        p_phone IN VARCHAR2 DEFAULT NULL,
        p_email IN VARCHAR2 DEFAULT NULL
    );
END customer_mgmt_pkg;
/

CREATE OR REPLACE PACKAGE BODY customer_mgmt_pkg AS
    PROCEDURE create_customer(
        p_name IN VARCHAR2,
        p_address IN VARCHAR2,
        p_phone IN VARCHAR2,
        p_email IN VARCHAR2,
        p_customer_id OUT NUMBER
    ) IS
    BEGIN
        -- This will only succeed if caller has INSERT privileges on CUSTOMERS
        p_customer_id := customer_id_seq.NEXTVAL;
        
        INSERT INTO customers (
            customer_id, customer_name, address, phone_number, email, created_by
        ) VALUES (
            p_customer_id, p_name, p_address, p_phone, p_email, USER
        );
        
        -- Log the activity using DEFINER package
        audit_pkg.log_activity(
            USER, 'CREATE', 'CUSTOMERS', p_customer_id, 
            NULL, 'New customer: ' || p_name
        );
        
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END create_customer;
    
    FUNCTION get_customer_details(
        p_customer_id IN NUMBER
    ) RETURN customers%ROWTYPE IS
        v_customer customers%ROWTYPE;
    BEGIN
        -- This will only succeed if caller has SELECT privileges on CUSTOMERS
        SELECT * INTO v_customer
        FROM customers
        WHERE customer_id = p_customer_id;
        
        -- Log the view activity 
        audit_pkg.log_activity(
            USER, 'VIEW', 'CUSTOMERS', p_customer_id, NULL, NULL
        );
        
        RETURN v_customer;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Customer not found');
    END get_customer_details;
    
    PROCEDURE update_customer(
        p_customer_id IN NUMBER,
        p_name IN VARCHAR2 DEFAULT NULL,
        p_address IN VARCHAR2 DEFAULT NULL,
        p_phone IN VARCHAR2 DEFAULT NULL,
        p_email IN VARCHAR2 DEFAULT NULL
    ) IS
        v_old_data CLOB;
        v_new_data CLOB;
        v_customer customers%ROWTYPE;
    BEGIN
        -- Get current data for audit
        SELECT * INTO v_customer 
        FROM customers 
        WHERE customer_id = p_customer_id
        FOR UPDATE;
        
        -- Convert to string for audit
        v_old_data := 'Name: ' || v_customer.customer_name || 
                      ', Address: ' || v_customer.address || 
                      ', Phone: ' || v_customer.phone_number || 
                      ', Email: ' || v_customer.email;
                      
        -- Update only provided fields
        UPDATE customers SET
            customer_name = NVL(p_name, customer_name),
            address = NVL(p_address, address),
            phone_number = NVL(p_phone, phone_number),
            email = NVL(p_email, email)
        WHERE customer_id = p_customer_id;
        
        -- Get updated data for audit
        SELECT * INTO v_customer 
        FROM customers 
        WHERE customer_id = p_customer_id;
        
        v_new_data := 'Name: ' || v_customer.customer_name || 
                      ', Address: ' || v_customer.address || 
                      ', Phone: ' || v_customer.phone_number || 
                      ', Email: ' || v_customer.email;
        
        -- Log the update activity
        audit_pkg.log_activity(
            USER, 'UPDATE', 'CUSTOMERS', p_customer_id, v_old_data, v_new_data
        );
        
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Customer not found');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END update_customer;
END customer_mgmt_pkg;
/

-- 6. Create INVOKER RIGHTS packages for transaction management
CREATE OR REPLACE PACKAGE transaction_pkg
AUTHID CURRENT_USER AS
    -- Available to tellers
    PROCEDURE create_transaction(
        p_account_id IN NUMBER,
        p_amount IN NUMBER,
        p_type IN VARCHAR2,
        p_description IN VARCHAR2,
        p_transaction_id OUT NUMBER
    );
    
    -- Only managers can approve high-value transactions due to role check
    PROCEDURE approve_transaction(
        p_transaction_id IN NUMBER
    );
    
    -- Auditors can view transaction details due to SELECT privileges
    FUNCTION get_transaction_details(
        p_transaction_id IN NUMBER
    ) RETURN transaction_details_rec;
    
    -- Helper function to check if current user has a specific role
    -- This is important for CURRENT_USER authorization
    FUNCTION has_role(p_role_name IN VARCHAR2) RETURN BOOLEAN;
END transaction_pkg;
/

CREATE OR REPLACE PACKAGE BODY transaction_pkg AS
    -- Helper function to check user roles
    FUNCTION has_role(p_role_name IN VARCHAR2) RETURN BOOLEAN IS
        v_result NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_result
        FROM user_role_privs
        WHERE granted_role = UPPER(p_role_name)
        AND username = USER;
        
        RETURN (v_result > 0);
    END has_role;

    PROCEDURE create_transaction(
        p_account_id IN NUMBER,
        p_amount IN NUMBER,
        p_type IN VARCHAR2,
        p_description IN VARCHAR2,
        p_transaction_id OUT NUMBER
    ) IS
        v_account accounts%ROWTYPE;
        v_status VARCHAR2(20);
    BEGIN
        -- Verify the account exists and get details
        SELECT * INTO v_account
        FROM accounts
        WHERE account_id = p_account_id
        FOR UPDATE; -- Lock the row
        
        -- Determine if transaction needs approval (high value)
        IF p_amount > 10000 THEN
            v_status := 'PENDING_APPROVAL';
        ELSE
            v_status := 'APPROVED';
            
            -- Update account balance for approved transactions
            IF p_type = 'DEPOSIT' THEN
                UPDATE accounts 
                SET balance = balance + p_amount 
                WHERE account_id = p_account_id;
            ELSIF p_type = 'WITHDRAWAL' THEN
                IF v_account.balance < p_amount THEN
                    RAISE_APPLICATION_ERROR(-20002, 'Insufficient funds');
                END IF;
                
                UPDATE accounts 
                SET balance = balance - p_amount 
                WHERE account_id = p_account_id;
            END IF;
        END IF;
        
        -- Create the transaction record
        p_transaction_id := transaction_id_seq.NEXTVAL;
        
        INSERT INTO transactions (
            transaction_id, account_id, amount, transaction_type,
            status, description, created_by
        ) VALUES (
            p_transaction_id, p_account_id, p_amount, p_type,
            v_status, p_description, USER
        );
        
        -- Log the activity
        audit_pkg.log_activity(
            USER, 'CREATE', 'TRANSACTIONS', p_transaction_id,
            NULL, 'New ' || p_type || ' transaction: $' || p_amount
        );
        
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Account not found');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END create_transaction;
    
    PROCEDURE approve_transaction(
        p_transaction_id IN NUMBER
    ) IS
        v_transaction transactions%ROWTYPE;
        v_account accounts%ROWTYPE;
    BEGIN
        -- First, check if user has manager role
        IF NOT has_role('BANK_MANAGER') THEN
            RAISE_APPLICATION_ERROR(-20003, 'Only managers can approve transactions');
        END IF;
        
        -- Get transaction details
        SELECT * INTO v_transaction
        FROM transactions
        WHERE transaction_id = p_transaction_id
        AND status = 'PENDING_APPROVAL'
        FOR UPDATE;
        
        -- Get account details
        SELECT * INTO v_account
        FROM accounts
        WHERE account_id = v_transaction.account_id
        FOR UPDATE;
        
        -- Process transaction based on type
        IF v_transaction.transaction_type = 'DEPOSIT' THEN
            UPDATE accounts 
            SET balance = balance + v_transaction.amount 
            WHERE account_id = v_transaction.account_id;
        ELSIF v_transaction.transaction_type = 'WITHDRAWAL' THEN
            IF v_account.balance < v_transaction.amount THEN
                RAISE_APPLICATION_ERROR(-20002, 'Insufficient funds');
            END IF;
            
            UPDATE accounts 
            SET balance = balance - v_transaction.amount 
            WHERE account_id = v_transaction.account_id;
        END IF;
        
        -- Update transaction status
        UPDATE transactions
        SET status = 'APPROVED',
            approved_by = USER,
            approval_date = SYSDATE
        WHERE transaction_id = p_transaction_id;
        
        -- Log the approval
        audit_pkg.log_activity(
            USER, 'APPROVE', 'TRANSACTIONS', p_transaction_id,
            'PENDING_APPROVAL', 'APPROVED'
        );
        
        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20004, 'Transaction not found or not pending approval');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END approve_transaction;
    
    FUNCTION get_transaction_details(
        p_transaction_id IN NUMBER
    ) RETURN transaction_details_rec IS
        v_result transaction_details_rec;
    BEGIN
        -- This will only succeed if caller has SELECT privileges on these tables
        SELECT transaction_details_rec(
            t.transaction_id,
            t.account_id,
            c.customer_id,
            c.customer_name,
            t.amount,
            t.transaction_type,
            t.status,
            t.created_by,
            t.creation_date,
            t.approved_by,
            t.approval_date
        ) INTO v_result
        FROM transactions t
        JOIN accounts a ON t.account_id = a.account_id
        JOIN customers c ON a.customer_id = c.customer_id
        WHERE t.transaction_id = p_transaction_id;
        
        -- Log the view activity
        audit_pkg.log_activity(
            USER, 'VIEW', 'TRANSACTIONS', p_transaction_id, NULL, NULL
        );
        
        RETURN v_result;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20005, 'Transaction not found');
    END get_transaction_details;
END transaction_pkg;
/

-- 7. Grant privileges to roles
-- Tellers - can create customers and transactions
GRANT SELECT, INSERT ON customers TO bank_teller;
GRANT SELECT ON accounts TO bank_teller;
GRANT SELECT, INSERT ON transactions TO bank_teller;
GRANT EXECUTE ON customer_mgmt_pkg TO bank_teller;
GRANT EXECUTE ON transaction_pkg TO bank_teller;

-- Managers - can do everything tellers can, plus approvals and updates
GRANT SELECT, INSERT, UPDATE ON customers TO bank_manager;
GRANT SELECT, UPDATE ON accounts TO bank_manager;
GRANT SELECT, INSERT, UPDATE ON transactions TO bank_manager;
GRANT EXECUTE ON customer_mgmt_pkg TO bank_manager;
GRANT EXECUTE ON transaction_pkg TO bank_manager;

-- Auditors - can only view data, not modify it
GRANT SELECT ON customers TO bank_auditor;
GRANT SELECT ON accounts TO bank_auditor;
GRANT SELECT ON transactions TO bank_auditor;
GRANT SELECT ON audit_logs TO bank_auditor;
GRANT EXECUTE ON transaction_pkg.get_transaction_details TO bank_auditor;
GRANT EXECUTE ON customer_mgmt_pkg.get_customer_details TO bank_auditor;
GRANT EXECUTE ON audit_pkg.view_audit_logs TO bank_auditor;

-- All roles need to execute the logging procedure
GRANT EXECUTE ON audit_pkg.log_activity TO bank_teller, bank_manager, bank_auditor;

-- 8. Example usage
-- Create sample users (would normally be done by system admin)
-- CREATE USER teller1 IDENTIFIED BY password;
-- CREATE USER manager1 IDENTIFIED BY password;
-- CREATE USER auditor1 IDENTIFIED BY password;

-- GRANT bank_teller TO teller1;
-- GRANT bank_manager TO manager1;
-- GRANT bank_auditor TO auditor1;
