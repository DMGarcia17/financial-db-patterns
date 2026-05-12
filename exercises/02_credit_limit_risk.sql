select cardholder_name,
       account_number,
       credit_limit,
       current_balance,
       (v.credit_limit - v.current_balance)                                                              available_credit,
       usage_percent,
       (case when usage_percent between 70 and 90 then 'MEDIUM' when usage_percent > 90 then 'HIGH' end) risk
from (select round(cb.current_balance / coalesce(a.credit_limit, 0) * 100, 2) usage_percent,
             c.cardholder_name,
             a.account_number,
             coalesce(a.credit_limit, 0)                                      credit_limit,
             cb.current_balance                                               current_balance
      from cards.account a
               inner join cards.card c on a.id = c.account_id
               inner join LATERAL (select a.id, transactions.fn_get_realtime_balance(a.id) current_balance) cb
                          on cb.id = a.id
      where a.credit_limit > 0) v
where usage_percent >= 70;