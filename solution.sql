drop table if exists order_log cascade;
drop table if exists order_items cascade;
drop table if exists orders cascade;
drop table if exists products cascade;
drop table if exists customers cascade;

create table customers (
    customer_id serial primary key,
    full_name varchar(100) not null,
    email varchar(100) unique not null,
    balance numeric(10,2) default 0
);

create table products (
    product_id serial primary key,
    product_name varchar(100) not null,
    price numeric(10,2) not null,
    stock_quantity int not null
);

create table orders (
    order_id serial primary key,
    customer_id int references customers(customer_id),
    order_date timestamp default current_timestamp,
    total_amount numeric(10,2) default 0
);

create table order_items (
    order_item_id serial primary key,
    order_id int references orders(order_id),
    product_id int references products(product_id),
    quantity int not null,
    price numeric(10,2) not null
);

create table order_log (
    log_id serial primary key,
    order_id int,
    customer_id int,
    action varchar(50),
    log_date timestamp default current_timestamp
);

--1 function to calculate order total

create or replace function calculate_order_total(p_order_id int)
returns numeric
language sql as $$
    select coalesce(sum(quantity * price), 0)
    from order_items
    where order_id = p_order_id;
$$;
--2 procedure to create order

create or replace procedure create_order(p_customer_id int)
language plpgsql as $$
begin
    if not exists (select 1 from customers where customer_id = p_customer_id) then
        raise exception 'customer % not found', p_customer_id;
    end if;
    insert into orders (customer_id, total_amount)
    values (p_customer_id, 0);
end;
$$;

--3 procedure to add product to order

create or replace procedure add_product_to_order(p_order_id int, p_product_id int, p_quantity int)
language plpgsql as $$
declare
    v_price numeric(10,2);
    v_stock int;
begin
    if p_quantity <= 0 then
        raise exception 'quantity must be greater than 0';
    end if;

    if not exists (select 1 from orders where order_id = p_order_id) then
        raise exception 'order % not found', p_order_id;
    end if;

    select price, stock_quantity into v_price, v_stock
    from products where product_id = p_product_id;

    if not found then
        raise exception 'product % not found', p_product_id;
    end if;

    if v_stock < p_quantity then
        raise exception 'not enough stock: available %, requested %', v_stock, p_quantity;
    end if;

    insert into order_items (order_id, product_id, quantity, price)
    values (p_order_id, p_product_id, p_quantity, v_price);
    update products set stock_quantity = stock_quantity - p_quantity
    where product_id = p_product_id;
end;
$$;

--4 trigger to update order total

create or replace function update_order_total()
returns trigger language plpgsql as $$
begin
    update orders
    set total_amount = calculate_order_total(
        case when TG_OP = 'DELETE' then OLD.order_id else NEW.order_id end
    )
    where order_id = case when TG_OP = 'DELETE' then OLD.order_id else NEW.order_id end;
    return null;
end;
$$;

create trigger trg_update_order_total
after insert or update or delete on order_items
for each row execute function update_order_total();

--5 trigger for audit log

create or replace function order_audit_log()
returns trigger language plpgsql as $$
begin
    insert into order_log (order_id, customer_id, action)
    values (NEW.order_id, NEW.customer_id, 'ORDER_CREATED');
    return NEW;
end;
$$;

create trigger trg_order_audit_log
after insert on orders
for each row execute function order_audit_log();

--6 tests
insert into customers (full_name, email, balance) values ('Alice Johnson', 'alice@example.com', 150.00);
insert into products (product_name, price, stock_quantity) values ('Laptop', 999.99, 10), ('Mouse', 25.00, 50);

call create_order(1);
call add_product_to_order(1, 1, 2);
call add_product_to_order(1, 2, 3);

select * from orders;
select * from order_log;
select product_name, stock_quantity from products;
update order_items set quantity = 1 where order_id = 1 and product_id = 1;
select order_id, total_amount from orders where order_id = 1;
delete from order_items where order_id = 1 and product_id = 2;
select order_id, total_amount from orders where order_id = 1;
