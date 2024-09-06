database_user="postgres"
database_name="deliverydb"

create_database="create database deliverydb"

delivery_insert=$(cat <<EOF
drop table if exists deliveries;

create table deliveries (
    id text primary key not null,
    order_number text not null,
    merchant_id text not null,
    estimated_delivery_date timestamptz not null,
    origin json not null,
    destination json not null,
    contact_info json not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    UNIQUE (merchant_id, order_number)	
);

create index deliveries_merchant_id_idx on deliveries(merchant_id);

create table deliveries_processing_queue (
    processing_queue_id serial primary key not null,
    id text not null,
    order_number text not null,
    merchant_id text not null,
    estimated_delivery_date timestamptz not null,
    origin json not null,
    destination json not null,
    contact_info json not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    processing_queue_timestamp timestamptz not null default now(),
    error_message text,
    error text,
    operation text not null,
);

create index deliveries_processing_queue_merchant_id_idx on deliveries(merchant_id);

create table deliveries_journal (
    journal_id SERIAL primary key not null,
    processing_queue_id text not null,
    id text not null,
    order_number text not null,
    merchant_id text not null,
    estimated_delivery_date timestamptz not null,
    origin json not null,
    destination json not null,
    contact_info json not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    journal_timestamp timestamptz not null,
    journal_operation text not null,
);

create index deliveries_journal_merchant_id_order_number_idx on deliveries(merchant_id, order_number);

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


queue_deliveries_insert_trigger_function=$(cat <<EOF
create or replace function deliveries_queue_insert_trigger_function()
returns trigger as \$\$
    
begin if (
  TG_OP = 'UPDATE' 
  and (old.id != new.id)
) then raise exception 'Table[deliveries] is journaled. Updates to primary key column[id] are not supported as this would make it impossible to follow the history of this row in the journal table[deliveries_processing_queue]';
end if;

insert into deliveries_processing_queue (
  id,
  order_number,
  merchant_id, 
  estimated_delivery_date,
  origin,
  destination,
  contact_info,
  created_at,
  updated_at,
  processing_queue_timestamp,
  operation
) 

values(
  new.id,
  new.order_number,
  new.merchant_id, 
  new.estimated_delivery_date,
  new.origin,
  new.destination,
  new.contact_info,
  new.created_at,
  new.updated_at,
  now(),
  TG_OP
);

return null;
end;

\$\$ LANGUAGE plpgsql;
EOF
)

queue_deliveries_delete_trigger_function=$(cat <<EOF
create or replace function deliveries_queue_delete_trigger_function()
returns trigger as \$\$
    
begin if (
  TG_OP = 'UPDATE' 
  and (old.id != new.id)
) then raise exception 'Table[deliveries] is journaled. Updates to primary key column[id] are not supported as this would make it impossible to follow the history of this row in the journal table[deliveries_processing_queue]';
end if;

insert into deliveries_processing_queue (
  id,
  order_number,
  merchant_id, 
  estimated_delivery_date,
  origin,
  destination,
  contact_info,
  created_at,
  updated_at,
  processing_queue_timestamp,
  operation
) 

values(
  old.id,
  old.order_number,
  old.merchant_id, 
  old.estimated_delivery_date,
  old.origin,
  old.destination,
  old.contact_info,
  old.created_at,
  old.updated_at,
  now(),
  TG_OP
);

return null;
end;

\$\$ LANGUAGE plpgsql;
EOF
)


create_triggers=$(cat <<EOF
create trigger deliveries_updated_at_trigger
BEFORE UPDATE on deliveries
FOR EACH ROW 
EXECUTE function set_updated_at_trigger_function();

create trigger deliveries_queue_insert_trigger
AFTER INSERT OR UPDATE on deliveries
FOR EACH ROW 
EXECUTE function deliveries_queue_insert_trigger_function();

create trigger deliveries_queue_delete_trigger
AFTER DELETE on deliveries
FOR EACH ROW 
EXECUTE function deliveries_queue_delete_trigger_function();

EOF
)

sql_commands="$delivery_insert $create_set_updated_at_trigger_function $queue_deliveries_insert_trigger_function $queue_deliveries_delete_trigger_function $create_triggers"

psql -U $database_user -c "$create_database"

psql -U $database_user -d $database_name -c "$sql_commands"
