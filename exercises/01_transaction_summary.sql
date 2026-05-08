select c.card_number,
       c.cardholder_name,
       count(ct.id) cant_trx,
       sum(case when ct.transaction_type in ('PUR', 'WIT') then ct.amount end) sum_amounts,
       sum(case when ct.transaction_type in ('PAY') then ct.amount end) payback,
       max(ct.created_at)
from cards.card c
         inner join transactions.card_transaction ct on c.id = ct.card_id
group by c.card_number, c.cardholder_name;