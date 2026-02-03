<null:handle $redis.handle()>
<null:keys $handle.keys('*')>

<foreach --define-index=i --start-index=0 $keys>
 [<var $i>] <var $_><br/>
</foreach>

