database_user="postgres"

database_name="deliverydb"

sudo su postgres -c "psql -U postgres -tc \"SELECT 1 FROM pg_database WHERE datname = 'deliverydb'\" | \
  grep -q 1 || psql -U postgres -c \"CREATE DATABASE deliverydb\""
 

orders_insert=$(cat <<EOF
 
drop table if exists ec_orders;

create table ec_orders (

    id text primary key not null,

    number text not null,

    merchant_id text not null,

    total decimal not null,

    submitted_at timestamptz,

    created_at timestamptz not null default now(),

    updated_at timestamptz not null default now(),
    
    UNIQUE (merchant_id, number)

);
 

create index merchant_id_idx on ec_orders(merchant_id);

drop table if exists ec_orders_processing_queue;
 
create table ec_orders_processing_queue (

    processing_queue_id SERIAL primary key,    

    id text not null,

    number text not null,

    merchant_id text not null,

    total decimal not null,

    submitted_at timestamptz,

    created_at timestamptz not null,

    updated_at timestamptz not null,

    processing_queue_timestamp timestamptz not null default now(),

    error_message text default '',

    error text default '',

    operation text not null ,
    
    UNIQUE (merchant_id, number)

);
 
create index ec_orders_processing_queue_number_merchant_id_idx on ec_orders_processing_queue(number, merchant_id);
 
drop table if exists ec_orders_journal;
 
create table ec_orders_journal (

    journal_id SERIAL primary key not null,

    processing_queue_id text not null,

    id text not null,

    number text not null,

    merchant_id text not null,

    total decimal not null,

    submitted_at timestamptz,

    created_at timestamptz not null,

    updated_at timestamptz not null,

    journal_timestamp timestamptz not null default now(),

    operation text not null,
    
    UNIQUE (merchant_id, number)

);
 
create index ec_orders_journal_number_merchant_id_idx on ec_orders_journal(number, merchant_id);
 
EOF

)
 
 
create_set_updated_at_trigger_function=$(cat <<EOF

create or replace function set_updated_at_trigger_function() 

returns trigger as \$\$

    BEGIN

        new.updated_at = now()::timestamptz;

        return new;

    END;

\$\$ LANGUAGE plpgsql;
 
EOF

)
 
 
queue_orders_insert_trigger_function=$(cat <<EOF

create or replace function orders_queue_insert_trigger_function()

returns trigger as \$\$
 
begin 

if (

  TG_OP = 'UPDATE' 

  and (old.id != new.id)

) then raise exception 'Table[ec_orders] is journaled. Updates to primary key column[id] are not supported as this would make it impossible to follow the history of this row in the journal table[ec_orders_processing_queue]';

end if;

insert into ec_orders_processing_queue (

  operation,

  id,
  
  merchant_id, 

  number,

  total, 

  submitted_at,

  created_at,

  updated_at

) 

values 

  (

    TG_OP,

    new.id,

    new.merchant_id, 

    new.number,

    new.total,

    new.submitted_at,

    new.created_at, 

    new.updated_at

  );

return null;

END;
 
\$\$ LANGUAGE plpgsql;
 
EOF

)
 
 
queue_orders_delete_trigger_function=$(cat <<EOF

create or replace function orders_queue_delete_trigger_function()

returns trigger as \$\$
 
begin insert into ec_orders_processing_queue (

  operation, 

  id,

  merchant_id, 

  number,

  total,

  submitted_at,

  created_at, 

  updated_at

) 

values 

  (

    TG_OP,

    old.id,

    old.merchant_id, 

    old.number,

    old.total, 

    old.submitted_at,

    old.created_at, 

    old.updated_at

  );

return null;

end;
 
\$\$ LANGUAGE plpgsql;

EOF

)
 
create_updated_at_trigger=$(cat <<EOF

create trigger orders_updated_at_trigger

BEFORE UPDATE on ec_orders

FOR EACH ROW 

EXECUTE function set_updated_at_trigger_function();
 
EOF

)
 
create_processing_queue_insert_trigger=$(cat <<EOF

create trigger orders_queue_insert_trigger

AFTER INSERT OR UPDATE on ec_orders

FOR EACH ROW 

EXECUTE function orders_queue_insert_trigger_function();
 
EOF

)
 
 
create_processing_queue_delete_trigger=$(cat <<EOF

create trigger orders_queue_delete_trigger

AFTER DELETE on ec_orders

FOR EACH ROW 

EXECUTE function orders_queue_delete_trigger_function();
 
EOF

)
 
 
sql_commands="$orders_insert $create_set_updated_at_trigger_function $queue_orders_insert_trigger_function $queue_orders_delete_trigger_function $create_updated_at_trigger $create_processing_queue_insert_trigger $create_processing_queue_delete_trigger"
 
psql -U $database_user -c "$create_database"
 
psql -U $database_user -d $database_name -c "$sql_commands"
