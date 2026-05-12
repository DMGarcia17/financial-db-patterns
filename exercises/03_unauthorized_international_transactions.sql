select c.cardholder_name,
       c.id,
       c.card_number,
       trx.created_at trx_date,
       trx.amount,
       trx.merchant_country,
       trx.merchant_name,
       (case
            when ctr.id is not null and trx.created_at between ctr.departure_date and ctr.return_date then 'AUTHORIZED'
            else 'UNAUTHORIZED INTERNATIONAL TRANSACTION'
           end)
from cards.card c
         inner join transactions.card_transaction trx on c.id = trx.card_id
         left join cards.card_travel_report ctr
                   on c.id = ctr.card_id and trx.created_at between ctr.departure_date and ctr.return_date
where trx.is_international;