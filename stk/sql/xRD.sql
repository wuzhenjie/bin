--  kmysql <<< "source /root/bin/stk/sql/God.sql"
--  kmysql <<< "source /root/bin/stk/sql/xRD.sql"

delimiter //

DROP PROCEDURE IF EXISTS sp_cp_tbl //
CREATE PROCEDURE sp_cp_tbl(a_tbl_fr CHAR(32), a_tbl_to CHAR(32)) BEGIN
    -- CREATE TABLE newadmin LIKE admin;   
    -- INSERT INTO newadmin SELECT * FROM admin;  
    SET @sqls=concat('DROP TABLE IF EXISTS ', a_tbl_to);
    PREPARE stmt from @sqls; EXECUTE stmt;

    SET @sqls=concat('CREATE TABLE ', a_tbl_to, ' LIKE ', a_tbl_fr); 
    PREPARE stmt from @sqls; EXECUTE stmt;

    SET @sqls=concat('INSERT INTO ', a_tbl_to, ' SELECT * FROM ', a_tbl_fr);  
    PREPARE stmt from @sqls; EXECUTE stmt;
    -- SELECT @sqls;
END //

DROP PROCEDURE IF EXISTS sp_ema//
CREATE PROCEDURE sp_ema(a_tbl CHAR(32), a_x CHAR(20), 
                        a_ema CHAR(20), a_period INT) tag_ema:BEGIN
    DECLARE v_i         INT DEFAULT 1;
    DECLARE v_ema       DECIMAL(8,4) DEFAULT 0;
    DECLARE v_ema_prev  DECIMAL(8,4) DEFAULT 0;
    DECLARE v_k         DECIMAL(8,4) DEFAULT (2.0/(a_period+1));

    # EXECUTE @sqls中的INTO 子句中的变量必须是用户变量 @var
    # EXECUTE @sqls中的WHERE子句中的比较不可以两个都是变量
    # EXECUTE @sqls中的SET =子句中的赋值也是如此

    SET @v_x   = 0; 
    SET @v_len = 0;

    SET @sqls=concat('SELECT count(*) FROM ', a_tbl, ' INTO @v_len');
    PREPARE stmt from @sqls; EXECUTE stmt;

    loop_visit: REPEAT
        SET @sqls=concat('SELECT ', a_x, ' FROM ', a_tbl,' WHERE id=', v_i, ' INTO @v_x');
        PREPARE stmt from @sqls; EXECUTE stmt;

        SET v_ema = IF(v_i=1, @v_x, @v_x * v_k + v_ema_prev * (1-v_k));

        set @sqls=concat('UPDATE ', a_tbl, ' SET ', a_ema,' = ', v_ema, ' WHERE id=', v_i);
        PREPARE stmt from @sqls; EXECUTE stmt; -- DEALLOCATE PREPARE stmt;

        SET v_ema_prev = v_ema;
        SET v_i = v_i + 1;
    UNTIL v_i > @v_len END REPEAT;
END tag_ema//


DROP PROCEDURE IF EXISTS sp_macd//
CREATE PROCEDURE sp_macd(a_tbl CHAR(32), a_code INT(6) ZEROFILL) tag_macd:BEGIN
    DROP TABLE IF EXISTS macd;
    CREATE TABLE macd (
        id          INT(6) PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date        date NOT NULL,
        close       DECIMAL(6,2) NOT NULL DEFAULT 0,
        short_ema   DECIMAL(8,4) NOT NULL DEFAULT 0,
        long_ema    DECIMAL(8,4) NOT NULL DEFAULT 0,
        dif         DECIMAL(8,4) NOT NULL DEFAULT 0,
        dea         DECIMAL(8,4) NOT NULL DEFAULT 0,
        macd        DECIMAL(8,4) NOT NULL DEFAULT 0,
        INDEX(date)
    );

    SET @sqls=concat('INSERT INTO macd(code,date,close) SELECT code,date,close FROM ',
                        a_tbl, ' WHERE code = ', a_code);
    PREPARE stmt from @sqls; EXECUTE stmt;

    -- long short dea 26 12 9
    call sp_ema('macd', 'close', 'short_ema', 12);
    call sp_ema('macd', 'close', 'long_ema',  26);

    UPDATE  macd SET dif  = short_ema-long_ema;

    call sp_ema('macd', 'dif',   'dea',       9);

    UPDATE  macd SET macd = (dif -dea)*2 ;
END tag_macd//


/* 结果输出到表 kdj */
DROP PROCEDURE IF EXISTS sp_kdj//
CREATE PROCEDURE sp_kdj(a_tbl CHAR(32), a_code INT(6) ZEROFILL, a_N INT) 
tag_kdj:BEGIN
    DECLARE v_i         INT DEFAULT a_N;
    DECLARE v_rsv       DECIMAL(8,4) DEFAULT 0;
    DECLARE v_k         DECIMAL(8,4) DEFAULT 50;
    DECLARE v_d         DECIMAL(8,4) DEFAULT 50;
    DECLARE v_prev_k    DECIMAL(8,4) DEFAULT 50;
    DECLARE v_prev_d    DECIMAL(8,4) DEFAULT 50;
    DECLARE v_j         DECIMAL(8,4) DEFAULT 50;

    DECLARE v_close     DECIMAL(6,2) DEFAULT 0;
    DECLARE v_llv       DECIMAL(6,2) DEFAULT 0;
    DECLARE v_hhv       DECIMAL(6,2) DEFAULT 0;
    DECLARE v_len       DECIMAL(6,2) DEFAULT 0;

    DROP   TEMPORARY TABLE IF EXISTS kdj;
    CREATE TEMPORARY TABLE kdj (
        id          INT(6) PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date        date NOT NULL,
        open        DECIMAL(6,2) NOT NULL DEFAULT 0,
        close       DECIMAL(6,2) NOT NULL DEFAULT 0,
        high        DECIMAL(6,2) NOT NULL DEFAULT 0,
        low         DECIMAL(6,2) NOT NULL DEFAULT 0,
        rsv         DECIMAL(8,4) NOT NULL DEFAULT 0,
        k           DECIMAL(8,4) NOT NULL DEFAULT 0,
        d           DECIMAL(8,4) NOT NULL DEFAULT 0,
        j           DECIMAL(8,4) NOT NULL DEFAULT 0,
        INDEX(date)
    );

    -- 只要传入参数a_tbl有列(code,date,close,high,low)，即可调用kdj
    SET @sqls=concat('INSERT INTO kdj(code,date,open,close,high,low) ',
                        'SELECT code,date,open,close,high,low FROM ', a_tbl,
                        ' WHERE code=', a_code, ' and date > "2012-11-11"');
    PREPARE stmt from @sqls; EXECUTE stmt;

    SELECT count(*) FROM kdj INTO v_len;
    -- SELECT * FROM kdj;

    loop_visit: REPEAT
        SELECT close FROM kdj where id = v_i INTO v_close;
        SELECT max(high) from kdj where v_i-a_N < id and id <= v_i INTO v_hhv;
        SELECT min(low ) from kdj where v_i-a_N < id and id <= v_i INTO v_llv;

        SET v_rsv = 100*(v_close-v_llv)/(v_hhv-v_llv);
        SET v_k = (2*v_prev_k + v_rsv)/3;
        SET v_d = (2*v_prev_d + v_k)/3;
        SET v_j = 3*v_k - 2*v_d;

        UPDATE kdj SET rsv =  v_rsv WHERE id = v_i;
        UPDATE kdj SET k   =  v_k   WHERE id = v_i;
        UPDATE kdj SET d   =  v_d   WHERE id = v_i;
        UPDATE kdj SET j   =  v_j   WHERE id = v_i;

        SET v_i = v_i + 1;
        SET v_prev_k = v_k;
        SET v_prev_d = v_d;
    UNTIL v_i > v_len END REPEAT;
END tag_kdj//

DROP PROCEDURE IF EXISTS sp_create_tbl_9jian //
CREATE PROCEDURE sp_create_tbl_9jian() tag_tbl_9jian:BEGIN 
    DROP   TABLE IF EXISTS tbl_9jian;
    CREATE TABLE tbl_9jian (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date1       date NOT NULL DEFAULT 0,
        date2       date NOT NULL DEFAULT 0,
        off         INT  NOT NULL DEFAULT 0,
        open        DECIMAL(6,2) NOT NULL DEFAULT 0,
        low         DECIMAL(6,2) NOT NULL DEFAULT 0,    -- lchng = (low - avrg)/avrg
        close       DECIMAL(6,2) NOT NULL DEFAULT 0,
        volume      DECIMAL(12,2) NOT NULL DEFAULT 0,
        amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
        turnov      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        avrg        DECIMAL(6,2) NOT NULL DEFAULT 0,    -- avrg = sum(amount) / sum(volume)
        chng        DECIMAL(6,2) NOT NULL DEFAULT 0     -- chng = (close-open)/open
    );
END tag_tbl_9jian //

DROP PROCEDURE IF EXISTS sp_create_tbl_6mai //
CREATE PROCEDURE sp_create_tbl_6mai() tag_tbl_6mai:BEGIN 
    DROP   TABLE IF EXISTS tbl_6mai;
    CREATE TABLE tbl_6mai (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date1       date NOT NULL DEFAULT 0,
        date2       date NOT NULL DEFAULT 0,
        off         INT  NOT NULL DEFAULT 0,
        open        DECIMAL(6,2) NOT NULL DEFAULT 0,
        low         DECIMAL(6,2) NOT NULL DEFAULT 0,    -- lchng = (low - avrg)/avrg
        close       DECIMAL(6,2) NOT NULL DEFAULT 0,
        volume      DECIMAL(12,2) NOT NULL DEFAULT 0,
        amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
        turnov      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        avrg        DECIMAL(6,2) NOT NULL DEFAULT 0,    -- avrg = sum(amount) / sum(volume)
        chng        DECIMAL(6,2) NOT NULL DEFAULT 0     -- chng = (close-open)/open
    );
END tag_tbl_6mai //

DROP PROCEDURE IF EXISTS sp_create_tbl_taox //
CREATE PROCEDURE sp_create_tbl_taox() tag_tbl_taox:BEGIN 
    DROP   TABLE IF EXISTS tbl_taox;
    CREATE TABLE tbl_taox (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date_p      date NOT NULL DEFAULT 0,
        date_c      date NOT NULL DEFAULT 0,
        off_p       INT  NOT NULL DEFAULT 0,
        off_c       INT  NOT NULL DEFAULT 0,
        tnov_p      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        tnov_c      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        avrg_p      DECIMAL(6,2) NOT NULL DEFAULT 0,    -- previous 
        avrg_c      DECIMAL(6,2) NOT NULL DEFAULT 0,    -- curr avrg = sum(amount) / sum(volume)
        ratio       DECIMAL(6,2) NOT NULL DEFAULT 0,
        close       DECIMAL(6,2) NOT NULL DEFAULT 0,    
        wchng       DECIMAL(6,2) NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS tbl_rdiff (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date_p      date NOT NULL DEFAULT 0,
        date_c      date NOT NULL DEFAULT 0,
        off_p       INT  NOT NULL DEFAULT 0,
        off_c       INT  NOT NULL DEFAULT 0,
        tnov_p      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        tnov_c      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        avrg_p      DECIMAL(6,2) NOT NULL DEFAULT 0,    -- previous 
        avrg_c      DECIMAL(6,2) NOT NULL DEFAULT 0,    -- curr avrg = sum(amount) / sum(volume)
        ratio       DECIMAL(6,2) NOT NULL DEFAULT 0,
        close       DECIMAL(6,2) NOT NULL DEFAULT 0,    
        wchng       DECIMAL(6,2) NOT NULL DEFAULT 0,
        cdiff       DECIMAL(6,2) NOT NULL DEFAULT 0,
        rdiff       DECIMAL(6,2) NOT NULL DEFAULT 0,
        dbrat       DECIMAL(6,2) NOT NULL DEFAULT 0 
    );
    CREATE TABLE IF NOT EXISTS tbl_tao5 LIKE tbl_taox;
END tag_tbl_taox //

DROP PROCEDURE IF EXISTS sp_create_tbl_fbi //
CREATE PROCEDURE sp_create_tbl_fbi() tag_tbl_fbi:BEGIN 

    DROP   TEMPORARY TABLE IF EXISTS tempfb;
    CREATE TEMPORARY TABLE tempfb (
        id          int(6)          PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6)          ZEROFILL NOT NULL, 
        datetime    bigint(14)      NOT NULL DEFAULT 0, 
        trade       DECIMAL(6,2)    NOT NULL,
        volume      DECIMAL(10,2)   NOT NULL,
        amount      DECIMAL(12,2)   NOT NULL,
        INDEX(code,datetime)
    );

    CREATE TABLE IF NOT EXISTS tbl_fbi5 (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        datetime_p  bigint(14)      NOT NULL DEFAULT 0,
        datetime_c  bigint(14)      NOT NULL DEFAULT 0,
        off_p       INT  NOT NULL DEFAULT 0,
        off_c       INT  NOT NULL DEFAULT 0,
        tnov_p      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        tnov_c      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        avrg_p      DECIMAL(6,2) NOT NULL DEFAULT 0,    -- previous 
        avrg_c      DECIMAL(6,2) NOT NULL DEFAULT 0,    -- curr avrg = sum(amount) / sum(volume)
        ratio       DECIMAL(6,2) NOT NULL DEFAULT 0,
        close       DECIMAL(6,2) NOT NULL DEFAULT 0,    
        wchng       DECIMAL(6,2) NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS tbl_fdiff (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        datetime_p  bigint(14)      NOT NULL DEFAULT 0,
        datetime_c  bigint(14)      NOT NULL DEFAULT 0,
        off_p       INT  NOT NULL DEFAULT 0,
        off_c       INT  NOT NULL DEFAULT 0,
        tnov_p      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        tnov_c      DECIMAL(6,2) NOT NULL DEFAULT 0,    
        avrg_p      DECIMAL(6,2) NOT NULL DEFAULT 0,    -- previous 
        avrg_c      DECIMAL(6,2) NOT NULL DEFAULT 0,    -- curr avrg = sum(amount) / sum(volume)
        ratio       DECIMAL(6,2) NOT NULL DEFAULT 0,
        close       DECIMAL(6,2) NOT NULL DEFAULT 0,    
        wchng       DECIMAL(6,2) NOT NULL DEFAULT 0,
        cdiff       DECIMAL(6,2) NOT NULL DEFAULT 0,
        rdiff       DECIMAL(6,2) NOT NULL DEFAULT 0,
        dbrat        DECIMAL(6,2) NOT NULL DEFAULT 0 
    );

    -- CREATE TABLE IF NOT EXISTS tbl_fbi5 LIKE tbl_fbi;

END tag_tbl_fbi //

-- 使用TEMPORARY时效率提升5倍
-- ERROR 1137 (HY000): Can't reopen table: 'tempday', 因为使用了SELECT嵌套
-- SELECT close FROM tempday WHERE date=(SELECT max(date) FROM tempday);

-- ERROR 1005 (HY000): Can't create table 'tempday' (errno: 13)
-- chmod 0777 /tmp 以解决之

DROP PROCEDURE IF EXISTS sp_create_tempday //
CREATE PROCEDURE sp_create_tempday() tag_tempday:BEGIN 
    DROP   TEMPORARY TABLE IF EXISTS tempday;
    CREATE TEMPORARY TABLE tempday (
 -- DROP   TABLE IF EXISTS tempday;
 -- CREATE TABLE tempday (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date        date NOT NULL,
        yesc        DECIMAL(6,2) NOT NULL,
        open        DECIMAL(6,2) NOT NULL,
        high        DECIMAL(6,2) NOT NULL,
        low         DECIMAL(6,2) NOT NULL,
        close       DECIMAL(6,2) NOT NULL,
        volume      DECIMAL(12,2)NOT NULL,
        amount      DECIMAL(12,2)NOT NULL DEFAULT 0,
        INDEX(date)
    );
   #)engine memory;
END tag_tempday //

DROP PROCEDURE IF EXISTS sp_create_tbl_mavol5B25 //
CREATE PROCEDURE sp_create_tbl_mavol5B25() tag_mavol5B25:BEGIN 
    DROP TABLE IF EXISTS tbl_mavol5B25; -- for visit output
    CREATE TABLE tbl_mavol5B25(
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        close       DECIMAL(6,2)  NOT NULL DEFAULT 0,
        ma5         DECIMAL(6,2)  NOT NULL DEFAULT 0,        
        ma13        DECIMAL(6,2)  NOT NULL DEFAULT 0,
        ma25        DECIMAL(6,2)  NOT NULL DEFAULT 0,
        vol         DECIMAL(12,2) NOT NULL DEFAULT 0,
        vol5        DECIMAL(12,2) NOT NULL DEFAULT 0,
        vol13       DECIMAL(12,2) NOT NULL DEFAULT 0,
        vol25       DECIMAL(12,2) NOT NULL DEFAULT 0
    );
END tag_mavol5B25 //

DROP PROCEDURE IF EXISTS sp_create_tbl_ma240 //
CREATE PROCEDURE sp_create_tbl_ma240() tag_ma240:BEGIN 
    DROP TABLE IF EXISTS tbl_ma240; -- for visit output
    CREATE TABLE tbl_ma240(
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date        date NOT NULL,
        close       DECIMAL(6,2) NOT NULL DEFAULT 0,
        ma5         DECIMAL(6,3) NOT NULL DEFAULT 0,        
        ma13        DECIMAL(6,3) NOT NULL DEFAULT 0,        
        ma25        DECIMAL(6,3) NOT NULL DEFAULT 0,        
        ma60        DECIMAL(6,3) NOT NULL DEFAULT 0,
        ma120       DECIMAL(6,3) NOT NULL DEFAULT 0,
        ma240       DECIMAL(6,3) NOT NULL DEFAULT 0
    );
END tag_ma240 //

DROP PROCEDURE IF EXISTS sp_create_tempwek //
CREATE PROCEDURE sp_create_tempwek() tag_tempwek:BEGIN
    DROP TABLE IF EXISTS tempwek;
    CREATE TABLE tempwek (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date        date NOT NULL,
        open        DECIMAL(6,2) NOT NULL,
        high        DECIMAL(6,2) NOT NULL,
        low         DECIMAL(6,2) NOT NULL,
        close       DECIMAL(6,2) NOT NULL,
        INDEX(date)
    );
END tag_tempwek //

DROP PROCEDURE IF EXISTS sp_day //
CREATE PROCEDURE sp_day(a_tbl CHAR(32), a_code INT(6) ZEROFILL) tag_day:BEGIN
    call sp_create_tempday();
    INSERT INTO tempday(code,date,open,high,low,close) 
        SELECT code,date,open,high,low,close FROM day WHERE code=a_code;
END tag_day //

DROP PROCEDURE IF EXISTS sp_7day //
CREATE PROCEDURE sp_7day(a_tbl CHAR(32), a_code INT(6) ZEROFILL) tag_wk:BEGIN
    DECLARE v_today date DEFAULT CURDATE();
    DECLARE v_date0 date DEFAULT 0;  -- Monday
    DECLARE v_date7 date DEFAULT 0;  -- next Monday
    DECLARE v_weekbgn date DEFAULT 0;
    DECLARE v_weekend date DEFAULT 0;
    DECLARE v_open  DECIMAL(6,2) DEFAULT 0;
    DECLARE v_close DECIMAL(6,2) DEFAULT 0;
    DECLARE v_high  DECIMAL(6,2) DEFAULT 0;
    DECLARE v_low   DECIMAL(6,2) DEFAULT 0;
    DECLARE v_i     INT DEFAULT 0;

    call sp_create_tempwek();
    call sp_create_tempday();
    INSERT INTO tempday(code,date,open,high,low,close) 
        SELECT code,date,open,high,low,close FROM day WHERE code=a_code;

    SET v_date0 = SUBDATE(CURDATE(),WEEKDAY(CURDATE())+7*100); -- 100 weeks
    SET v_date7 = ADDDATE(v_date0, 7);
    -- SELECT v_date0;

    loop_visit: REPEAT
        SELECT min(date) FROM tempday WHERE  date >= v_date0 and date < v_date7 INTO v_weekbgn;
        SELECT max(date) FROM tempday WHERE  date >= v_date0 and date < v_date7 INTO v_weekend;

        SELECT  open FROM tempday where date = v_weekbgn into v_open;
        SELECT close FROM tempday where date = v_weekend into v_close;
        SELECT max(high) FROM tempday where date >= v_weekbgn and date <= v_weekend into v_high;
        SELECT min(low)  FROM tempday where date >= v_weekbgn and date <= v_weekend into v_low;

        IF v_weekbgn IS NOT NULL THEN
            IF v_high IS NULL THEN
                SELECT v_weekbgn, v_weekend;
                LEAVE tag_wk;
            END IF;

            INSERT INTO tempwek(code,date,open,high,low,close)
                    VALUES(a_code, v_weekend, v_open, v_high, v_low, v_close);
            -- ELSE SELECT v_weekend, " is market-closed";
        END IF;

        SET v_date0 = v_date7;
        SET v_date7 = ADDDATE(v_date0, 7);
        SET v_i = v_i + 1;
        --  IF (v_i > 81) THEN
        --      SELECT "leaveing with count 60"; LEAVE loop_visit; 
        --  END IF;
    UNTIL v_date0 >= v_today END REPEAT;
    -- SELECT v_date7, v_today;
END tag_wk //

DROP PROCEDURE IF EXISTS sp_kdj_wk//
CREATE PROCEDURE sp_kdj_wk(a_tbl CHAR(32), a_code INT(6) ZEROFILL, a_N INT) 
tag_kdj_wk:BEGIN
    call sp_7day(a_tbl, a_code);
    call sp_kdj('tempwek', a_code, 9);
END tag_kdj_wk //

DROP PROCEDURE IF EXISTS sp_flt_kdj_up//
CREATE PROCEDURE sp_flt_kdj_up(a_code INT(6) ZEROFILL) tag_flt_kdj_up:BEGIN
    DECLARE v_maxid     INT;
    DECLARE v_date      DATE;
    DECLARE v_k2    DECIMAL(8,4) DEFAULT 0;
    DECLARE v_k0    DECIMAL(8,4) DEFAULT 0;
    DECLARE v_d2    DECIMAL(8,4) DEFAULT 0;
    DECLARE v_d0    DECIMAL(8,4) DEFAULT 0;

    call sp_kdj('day', a_code, 9);
    SELECT max(id) FROM kdj INTO v_maxid;
    SELECT k,d      FROM kdj WHERE id=(v_maxid-2)  INTO v_k0,v_d0;
    SELECT k,d,date FROM kdj WHERE id=v_maxid      INTO v_k2,v_d2,v_date;

    -- K上穿D, d<30, and ALIVE
    IF v_k2 > v_d2 AND v_k0 < v_d0 AND v_d2 < 35 AND v_date = @v_maxdate THEN 
        SELECT "coming ", a_code;
        INSERT INTO tbl_visit(code) VALUES(a_code);
    END IF;
END tag_flt_kdj_up //

DROP PROCEDURE IF EXISTS sp_visit_tbl//
CREATE PROCEDURE sp_visit_tbl(a_tbl CHAR(32), a_type INT) tag_visit:BEGIN
    DECLARE v_code  INT(6) ZEROFILL;
    DECLARE v_id    INT DEFAULT 1; 
    DECLARE v_len   INT; /* CURSOR and HANDLER declare in end of declaration */
    
    DROP TABLE IF EXISTS codes;
    CREATE TABLE codes (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0
    );
    DROP TABLE IF EXISTS tbl_visit; -- for visit output
    CREATE TABLE tbl_visit(
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        swing       DECIMAL(6,2) NOT NULL DEFAULT 0,        -- price swing
        rise        DECIMAL(6,2) NOT NULL DEFAULT 0,
        sink        DECIMAL(6,2) NOT NULL DEFAULT 0,
        bounce      DECIMAL(6,2) NOT NULL DEFAULT 0,        -- net turnover
        amount      DECIMAL(12,2)NOT NULL DEFAULT 0,
        turnover    DECIMAL(6,2) NOT NULL DEFAULT 0,        -- sum turnover
        date_low    date NOT NULL DEFAULT 0,
        date_high   date NOT NULL DEFAULT 0
    );

    SET @cond=' ORDER by code';
    SET @sqls=concat('INSERT INTO codes(code) SELECT code FROM ', a_tbl, @cond);
    PREPARE stmt from @sqls; EXECUTE stmt;
    SELECT max(id)   FROM codes INTO v_len;
    SELECT max(date) FROM day WHERE code=900001 INTO @v_maxdate;

    SET @sqls=concat(
    'SELECT date FROM day WHERE code = 900001 ORDER by date DESC limit ',
    @argv_n,
    ',1 INTO @v_mindate;'
    );
    PREPARE stmt from @sqls; EXECUTE stmt;

    -- prepare
    IF a_type = @fn_mavol5B25       THEN call sp_create_tbl_mavol5B25();END IF;
    IF a_type = @fn_ma60x2x4        THEN call sp_create_tbl_ma240();    END IF;
    IF a_type = @fn_dugu9jian       THEN call sp_create_tbl_9jian();    END IF;
    IF a_type = @fn_6maishenjian    THEN call sp_create_tbl_6mai();     END IF;
    IF a_type = @fn_taox_ratio      THEN call sp_create_tbl_taox();     END IF;
    IF a_type = @fn_fbi_ratio       THEN call sp_create_tbl_fbi();      END IF;

    -- visit all codes
    WHILE v_id <= v_len DO
        SELECT code FROM codes WHERE id=(v_id) INTO v_code;
        CASE a_type
            WHEN @fn_flt_kdj_up     THEN call sp_flt_kdj_up(v_code);
            WHEN @fn_dugu9jian      THEN call sp_dugu9jian(v_code);
            WHEN @fn_mavol5B25      THEN call sp_mavol5B25(v_code);
            WHEN @fn_ma60x2x4       THEN call sp_ma60x240(v_code);
            WHEN @fn_ma5B25         THEN call sp_ma5B25(v_code);
            WHEN @fn_6maishenjian   THEN call sp_6maishenjian(v_code);
            WHEN @fn_taox_ratio     THEN call sp_taox(v_code);
            WHEN @fn_fbi_ratio      THEN call sp_fbi(v_code);
            ELSE SELECT "no a_type match";
        END CASE;

        SET v_id = v_id + 1;
    END WHILE;
END tag_visit //

DROP PROCEDURE IF EXISTS sp_xRD//
CREATE PROCEDURE sp_xRD() tag_xRD:BEGIN
    DECLARE v_code      INT(6) ZEROFILL DEFAULT 0;
    DECLARE v_xRD_date  date DEFAULT 0;
    DECLARE v_min_date  date DEFAULT 0;
    DECLARE v_yesclose  DECIMAL(6,2) DEFAULT 0;
    DECLARE v_xRD_open  DECIMAL(6,2) DEFAULT 0;
    DECLARE v_facttor   DECIMAL(8,4) DEFAULT 0;

    DECLARE v_unit_xRD   DECIMAL(8,5) DEFAULT 0;
    DECLARE v_price_chg  DECIMAL(8,5) DEFAULT 0;

 -- SELECT v_code,v_min_date,v_xRD_date;
 -- SELECT song_ratio,pei_ratio,pei_price,div_ratio FROM xRD WHERE code = v_code ;
    SELECT code,date FROM tempday WHERE id=1 INTO v_code,v_min_date;
    SELECT date FROM xRD WHERE code=(v_code) INTO v_xRD_date;

    IF  v_xRD_date < '2013-01-01' OR v_xRD_date < v_min_date OR 
        v_xRD_date > CURDATE() THEN 
        LEAVE tag_xRD; 
    END IF;

    -- begin to UPDATE, 对每个close进行相应公式处理。
    SELECT close FROM tempday 
        WHERE id=(SELECT id FROM tempday WHERE date=v_xRD_date)-1 INTO v_yesclose;

    SELECT (1+song_ratio+pei_ratio),(pei_price*pei_ratio-div_ratio) 
        FROM xRD WHERE code = v_code INTO v_unit_xRD,v_price_chg;

--  SELECT date,close,(close+v_price_chg)/v_unit_xRD
--      FROM tempday WHERE date < v_xRD_date and date > '2013-10-30';

    UPDATE tempday SET 
        close=(close+v_price_chg)/v_unit_xRD,
         open=(open +v_price_chg)/v_unit_xRD,
         high=(high +v_price_chg)/v_unit_xRD,
          low=(low  +v_price_chg)/v_unit_xRD 
        WHERE date < v_xRD_date;
    -- SELECT date,close FROM tempday;

END tag_xRD //

DROP PROCEDURE IF EXISTS sp_stat_change //
CREATE PROCEDURE sp_stat_change() tag_stat_change:BEGIN
    DECLARE v_sink      INT DEFAULT 0; 
    DECLARE v_rise      INT DEFAULT 0; 
    DECLARE v_len       INT DEFAULT 0; 
    DECLARE v_start     date DEFAULT 0;
    DECLARE v_tmpdate   date DEFAULT 0;

    DECLARE v_inc       INT DEFAULT 0; 
    DECLARE v_dec0      INT DEFAULT 0; 

    DECLARE v_inc8p      INT DEFAULT 0; 
    DECLARE v_inc58      INT DEFAULT 0; 
    DECLARE v_inc25      INT DEFAULT 0; 
    DECLARE v_inc02      INT DEFAULT 0; 

    DECLARE v_dec25      INT DEFAULT 0; 
    DECLARE v_dec58      INT DEFAULT 0; 
    DECLARE v_dec8p      INT DEFAULT 0; 
    DECLARE v_dec02      INT DEFAULT 0; 

    DROP TABLE IF EXISTS tbl_change;
    CREATE TABLE IF NOT EXISTS tbl_change (
        id          INT(6) PRIMARY key AUTO_INCREMENT NOT NULL,
        code        INT(6) ZEROFILL NOT NULL DEFAULT 0,
        date        date NOT NULL,
        chng        DECIMAL(6,2) NOT NULL DEFAULT 0
    );

    DROP TABLE IF EXISTS tbl_stat_change;
    CREATE TABLE IF NOT EXISTS tbl_stat_change (
        id          INT(6) PRIMARY key AUTO_INCREMENT NOT NULL,
        date        date NOT NULL,

        inc         INT(6) NOT NULL DEFAULT 0,
        dec0        INT(6) NOT NULL DEFAULT 0,

        inc8p        INT(6) NOT NULL DEFAULT 0,
        inc58        INT(6) NOT NULL DEFAULT 0,
        inc25        INT(6) NOT NULL DEFAULT 0,
        inc02        INT(6) NOT NULL DEFAULT 0,

        dec02        INT(6) NOT NULL DEFAULT 0,
        dec25        INT(6) NOT NULL DEFAULT 0,
        dec58        INT(6) NOT NULL DEFAULT 0,
        dec8p        INT(6) NOT NULL DEFAULT 0
    );

    INSERT INTO tbl_change(code,date,chng) SELECT 
           code,date,100*(close-yesc)/yesc FROM day 
            WHERE date>=@START and date<=@END; # and code>300000 and code<400000;

    SET v_start=@START;

    -- @START 这天没有进入统计
    WHILE v_start <> @END DO
        SELECT date FROM day WHERE code=900001 and date>v_start limit 1 INTO v_start;
        -- SELECT v_start;

        SELECT count(code) FROM tbl_change WHERE date=v_start and chng>=0              INTO v_inc;
        SELECT count(code) FROM tbl_change WHERE date=v_start and chng<0               INTO v_dec0;
        SELECT count(code) FROM tbl_change WHERE date=v_start and chng>=8              INTO v_inc8p;
        SELECT count(code) FROM tbl_change WHERE date=v_start and chng<8 and chng>=5   INTO v_inc58;
        SELECT count(code) FROM tbl_change WHERE date=v_start and chng<5 and chng>=2   INTO v_inc25;
        SELECT count(code) FROM tbl_change WHERE date=v_start and chng<2 and chng>=0   INTO v_inc02;
        SELECT count(code) FROM tbl_change WHERE date=v_start and chng<0  and chng>=-2 INTO v_dec02;
        SELECT count(code) FROM tbl_change WHERE date=v_start and chng<-2 and chng>=-5 INTO v_dec25;
        SELECT count(code) FROM tbl_change WHERE date=v_start and chng<-5 and chng>=-8 INTO v_dec58;
        SELECT count(code) FROM tbl_change WHERE date=v_start and chng<-8              INTO v_dec8p;

        INSERT INTO tbl_stat_change(date, inc, dec0, 
                inc8p ,inc58 ,inc25 ,inc02 ,dec02 ,dec25 ,dec58 ,dec8p )
        VALUES(v_start, v_inc, v_dec0, 
                v_inc8p ,v_inc58 ,v_inc25 ,v_inc02 ,v_dec02 ,v_dec25 ,v_dec58 ,v_dec8p );
        -- LEAVE tag_stat_change;
    END WHILE;

END tag_stat_change //

-- 暂时不进行除权处理

DROP PROCEDURE IF EXISTS sp_dugu9jian//
CREATE PROCEDURE sp_dugu9jian(a_code INT(6) ZEROFILL) tag_9jian:BEGIN
    -- 9jian
    DECLARE v_id        INT DEFAULT 1; 
    DECLARE v_open      DECIMAL(6,2) DEFAULT 0;
    DECLARE v_close     DECIMAL(6,2) DEFAULT 0;
    DECLARE v_chng      DECIMAL(8,2) DEFAULT 0;
    DECLARE v_low       DECIMAL(8,2) DEFAULT 0;
    DECLARE v_avrg      DECIMAL(8,2) DEFAULT 0;
    DECLARE v_date1     DATE DEFAULT NULL;
    DECLARE v_date2     DATE DEFAULT NULL;
    DECLARE v_shares    INT DEFAULT 0;
    DECLARE v_shares0   INT DEFAULT 0;
    DECLARE v_volume    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_amount    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sumvolume DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sumamount DECIMAL(12,2) DEFAULT 0;
    DECLARE v_turnov    DECIMAL(12,2) DEFAULT 0;

    call sp_create_tempday();
    SELECT nmc/close FROM cap WHERE code=a_code LIMIT 1 INTO v_shares;
    SET v_shares0 = v_shares * @NMC_RATIO;
    -- 可以通过 turnover = latest(volume/shares); 来计算相应日期数 @NUM
    SET @sqls=concat('
        INSERT INTO tempday(code,date,yesc,open,high,low,close,volume,amount)
        SELECT code,date,yesc,open,high,low,close,volume,amount FROM day WHERE code=', 
        a_code, " and date<= '", @END, "' order by date DESC LIMIT ", @NUM);
    PREPARE stmt from @sqls; EXECUTE stmt;

    SELECT count(*)   FROM tempday INTO @v_len;
    SELECT date,close,low FROM tempday WHERE id=1 INTO v_date2,v_close,v_low;

    -- 过滤停牌很久的个股
    IF DATE_ADD(v_date2, INTERVAL 5 DAY) < @END THEN 
        # SELECT a_code, "a stop one";
        LEAVE tag_9jian; 
    END IF;

    lbl_upto_100: WHILE v_id <= @v_len DO
        SELECT volume,amount FROM tempday WHERE id=(v_id) INTO v_volume,v_amount;

        SET v_sumvolume = v_sumvolume + v_volume;
        SET v_sumamount = v_sumamount + v_amount;

        -- upto 100% turnover or 双周浮盈计算
        IF  v_sumvolume >= v_shares0 OR ((@NUM < 10) AND (v_id = @v_len)) THEN 
            SELECT date,yesc FROM tempday WHERE id=(v_id) INTO v_date1,v_open;
            SET v_avrg = (v_sumamount/v_sumvolume);
            SET v_chng = 100*(v_close-v_open)/v_open;
            SET v_turnov = 100*v_sumvolume/v_shares;
            -- SET v_wchng = 100*(v_close-v_avrg)/v_avrg;
            -- SELECT * FROM tempday;
            -- SELECT v_id;
            INSERT INTO tbl_9jian(code,date1,date2,off,open,low,close,
                            amount,volume,turnov,avrg,chng)
                     VALUES(a_code,v_date1,v_date2,v_id,v_open,v_low,v_close,
                            v_sumamount,v_sumvolume,v_turnov, v_avrg, v_chng);
            LEAVE lbl_upto_100; 
        END IF;

        SET v_id = v_id + 1;
    END WHILE lbl_upto_100;
END tag_9jian //

DROP PROCEDURE IF EXISTS sp_taox//
CREATE PROCEDURE sp_taox(a_code INT(6) ZEROFILL) tag_taox:BEGIN
    -- taox
    DECLARE v_cnt100    INT DEFAULT 0; 
    DECLARE v_id        INT DEFAULT 1; 
    DECLARE v_off_c     INT DEFAULT 1; 
    DECLARE v_off_p     INT DEFAULT 1; 

    DECLARE v_close     DECIMAL(6,2) DEFAULT 0;
    DECLARE v_ratio     DECIMAL(6,2) DEFAULT 0;
    DECLARE v_wchng     DECIMAL(6,2) DEFAULT 0;

    DECLARE v_avrg      DECIMAL(8,2) DEFAULT 0;
    DECLARE v_avrg_c    DECIMAL(8,2) DEFAULT 0;
    DECLARE v_avrg_p    DECIMAL(8,2) DEFAULT 0;

    DECLARE v_date      DATE DEFAULT NULL;
    DECLARE v_date_c    DATE DEFAULT NULL;
    DECLARE v_date_p    DATE DEFAULT NULL;

    DECLARE v_turnov    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_tnov_c  DECIMAL(12,2) DEFAULT 0;
    DECLARE v_tnov_p  DECIMAL(12,2) DEFAULT 0;

    DECLARE v_shares    INT DEFAULT 0;
    DECLARE v_shares0   INT DEFAULT 0;
    DECLARE v_volume    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_amount    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sumvolume DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sumamount DECIMAL(12,2) DEFAULT 0;


    call sp_create_tempday();
    SELECT nmc/close FROM cap WHERE code=a_code LIMIT 1 INTO v_shares;
    SET v_shares0 = v_shares * @NMC_RATIO;
    -- 可以通过 turnover = latest(volume/shares); 来计算相应日期数 @NUM
    SET @sqls=concat('
        INSERT INTO tempday(code,date,yesc,open,high,low,close,volume,amount)
        SELECT code,date,yesc,open,high,low,close,volume,amount FROM day WHERE code=', 
        a_code, " and date<= '", @END, "' order by date DESC LIMIT ", @NUM);
    PREPARE stmt from @sqls; EXECUTE stmt;

    SELECT count(*)   FROM tempday INTO @v_len;
    SELECT date,close FROM tempday WHERE id=1 INTO v_date,v_close;

    -- 过滤停牌很久的个股
    IF DATE_ADD(v_date, INTERVAL 5 DAY) < @END and @FORCE <> 1 THEN 
        SELECT a_code, @END, "a stop one";
        LEAVE tag_taox; 
    END IF;

    -- SELECT  v_shares0;

    lbl_upto_100: WHILE v_id <= @v_len DO
        SELECT volume,amount FROM tempday WHERE id=(v_id) INTO v_volume,v_amount;

        SET v_sumvolume = v_sumvolume + v_volume;
        SET v_sumamount = v_sumamount + v_amount;

        -- SELECT  v_sumvolume,v_sumamount;

        -- upto 100% turnover
        IF  v_sumvolume >= v_shares0 THEN 
            SET v_avrg = (v_sumamount/v_sumvolume);
            SET v_turnov = 100*v_sumvolume/v_shares;
            SET v_sumvolume = 0;
            SET v_sumamount = 0;

            IF  v_cnt100 = 0 THEN 
                -- SELECT v_id;
                SET v_cnt100 = 1;
                SET v_avrg_c    = v_avrg;
                SET v_tnov_c  = v_turnov;
                set v_off_c     = v_id;
                set v_date_c    = v_date;
                SET v_wchng     = 100 * (v_close-v_avrg_c)/v_avrg_c;
            ELSE
                SELECT date FROM tempday WHERE id=(v_off_c+1) INTO v_date;
                SET v_cnt100 = 2;
                SET v_avrg_p    = v_avrg;
                SET v_tnov_p  = v_turnov;
                SET v_off_p     = v_id - v_off_c;
                set v_date_p    = v_date;

                SET v_ratio     = 100 * (v_avrg_c-v_avrg_p) / v_avrg_c;
                INSERT INTO tbl_taox(code,  date_p,off_p,avrg_p,tnov_p, 
                                            date_c,off_c,avrg_c,tnov_c,ratio,close,wchng)
                         VALUES(a_code,   v_date_p,v_off_p,v_avrg_p,v_tnov_p, 
                                          v_date_c,v_off_c,v_avrg_c,v_tnov_c,v_ratio,v_close,v_wchng);

                INSERT INTO tbl_tao5(code,  date_p,off_p,avrg_p,tnov_p, 
                                            date_c,off_c,avrg_c,tnov_c,ratio,close,wchng)
                         VALUES(a_code,   v_date_p,v_off_p,v_avrg_p,v_tnov_p, 
                                          v_date_c,v_off_c,v_avrg_c,v_tnov_c,v_ratio,v_close,v_wchng);
                LEAVE lbl_upto_100;
            END IF;

        END IF;

        SET v_id = v_id + 1;
    END WHILE lbl_upto_100;

    IF v_cnt100 < 2 THEN
        -- 使用数据库文件实现EXIT_CODE
        -- SELECT a_code, "so_little_taox_data";
        INSERT INTO exitcode VALUES (1);
    END IF;
    -- SELECT v_cnt100;
END tag_taox //

DROP PROCEDURE IF EXISTS sp_fbi//
CREATE PROCEDURE sp_fbi(a_code INT(6) ZEROFILL) tag_fbi:BEGIN
    -- fbi
    DECLARE v_cnt100    INT DEFAULT 0;
    DECLARE v_id        INT DEFAULT 1;
    DECLARE v_off_c     INT DEFAULT 1;
    DECLARE v_off_p     INT DEFAULT 1;

    DECLARE v_trade     DECIMAL(6,2) DEFAULT 0;
    DECLARE v_ratio     DECIMAL(6,2) DEFAULT 0;
    DECLARE v_wchng     DECIMAL(6,2) DEFAULT 0;

    DECLARE v_avrg      DECIMAL(8,2) DEFAULT 0;
    DECLARE v_avrg_c    DECIMAL(8,2) DEFAULT 0;
    DECLARE v_avrg_p    DECIMAL(8,2) DEFAULT 0;

    DECLARE v_datetime   bigint(14) DEFAULT 0;
    DECLARE v_datetime_c bigint(14) DEFAULT 0;
    DECLARE v_datetime_p bigint(14) DEFAULT 0;

    DECLARE v_turnov    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_tnov_c  DECIMAL(12,2) DEFAULT 0;
    DECLARE v_tnov_p  DECIMAL(12,2) DEFAULT 0;

    DECLARE v_shares    INT DEFAULT 0;
    DECLARE v_shares0   INT DEFAULT 0;
    DECLARE v_volume    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_amount    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sumvolume DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sumamount DECIMAL(12,2) DEFAULT 0;

    SELECT nmc/close FROM cap WHERE code=a_code LIMIT 1 INTO v_shares;
    SET v_shares0 = 100 * v_shares * @NMC_RATIO;
    -- 可以通过 turnover = latest(volume/shares); 来计算相应日期数 @NUM
    SET @sqls=concat('
        INSERT INTO tempfb(code,datetime,trade,volume,amount)
        SELECT code,datetime,trade,volume,amount FROM fenbi WHERE code=', 
        a_code, " and datetime<= ", @DT, " order by datetime DESC LIMIT ", @NUM);
    PREPARE stmt from @sqls; EXECUTE stmt;

    SELECT count(*)   FROM tempfb INTO @v_len;
    SELECT datetime,trade FROM tempfb WHERE id=1 INTO v_datetime,v_trade;

    -- SELECT  v_shares0;

    lbl_upto_100: WHILE v_id <= @v_len DO
        SELECT volume,amount FROM tempfb WHERE id=(v_id) INTO v_volume,v_amount;

        SET v_sumvolume = v_sumvolume + v_volume;
        SET v_sumamount = v_sumamount + v_amount;

        -- SELECT  v_sumvolume,v_sumamount;

        -- upto 100% turnover
        IF  v_sumvolume >= v_shares0 THEN 
            SET v_avrg = (v_sumamount/v_sumvolume);
            SET v_turnov = v_sumvolume/v_shares;
            SET v_sumvolume = 0;
            SET v_sumamount = 0;

            IF  v_cnt100 = 0 THEN 
                -- SELECT v_id;
                SET v_cnt100 = 1;
                SET v_avrg_c    = v_avrg;
                SET v_tnov_c    = v_turnov;
                set v_off_c     = v_id;
                set v_datetime_c= v_datetime;
                SET v_wchng     = 100 * (v_trade-v_avrg_c)/v_avrg_c;
            ELSE
                SELECT datetime FROM tempfb WHERE id=(v_off_c+1) INTO v_datetime;
                SET v_cnt100 = 2;
                SET v_avrg_p    = v_avrg;
                SET v_tnov_p    = v_turnov;
                SET v_off_p     = v_id - v_off_c;
                set v_datetime_p= v_datetime;

                SET v_ratio     = 100 * (v_avrg_c-v_avrg_p) / v_avrg_c;
                INSERT INTO tbl_fbi5(code,  datetime_p,off_p,avrg_p,tnov_p, 
                                           datetime_c,off_c,avrg_c,tnov_c,ratio,close,wchng)
                         VALUES(a_code,   v_datetime_p,v_off_p,v_avrg_p,v_tnov_p, 
                                          v_datetime_c,v_off_c,v_avrg_c,v_tnov_c,v_ratio,v_trade,v_wchng);
                LEAVE lbl_upto_100;
            END IF;

        END IF;

        SET v_id = v_id + 1;
    END WHILE lbl_upto_100;

    IF v_cnt100 < 2 THEN
        -- 使用数据库文件实现EXIT_CODE
        -- SELECT a_code, "so_little_fbi_data";
        INSERT INTO exitcode VALUES (1);
    END IF;
    -- SELECT v_cnt100;
END tag_fbi //

DROP PROCEDURE IF EXISTS sp_6maishenjian//
CREATE PROCEDURE sp_6maishenjian(a_code INT(6) ZEROFILL) tag_6mai:BEGIN
    -- 6mai
    DECLARE v_id        INT DEFAULT 1; 
    DECLARE v_open      DECIMAL(6,2) DEFAULT 0;
    DECLARE v_close     DECIMAL(6,2) DEFAULT 0;
    DECLARE v_chng      DECIMAL(8,2) DEFAULT 0;
    DECLARE v_low       DECIMAL(8,2) DEFAULT 0;
    DECLARE v_avrg      DECIMAL(8,2) DEFAULT 0;
    DECLARE v_date1     DATE DEFAULT NULL;
    DECLARE v_date2     DATE DEFAULT NULL;
    DECLARE v_datemax   DATE DEFAULT NULL;
    DECLARE v_shares    INT DEFAULT 0;
    DECLARE v_shares0   INT DEFAULT 0;
    DECLARE v_volume    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_amount    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sumvolume DECIMAL(12,2) DEFAULT 0;
    DECLARE v_sumamount DECIMAL(12,2) DEFAULT 0;
    DECLARE v_turnov    DECIMAL(12,2) DEFAULT 0;

    call sp_create_tempday();
    SELECT nmc/close FROM cap WHERE code=a_code LIMIT 1 INTO v_shares;
    SET v_shares0 = v_shares * @NMC_RATIO;

    -- 可以通过 turnover = latest(volume/shares); 来计算相应日期数 @NUM
    SET @sqls=concat('
        INSERT INTO tempday(code,date,yesc,open,high,low,close,volume,amount)
        SELECT code,date,yesc,open,high,low,close,volume,amount FROM day WHERE code=', 
        a_code, " and date<= '", @END, "' order by date DESC LIMIT ", @NUM);
    PREPARE stmt from @sqls; EXECUTE stmt;

    SELECT count(*) FROM tempday INTO @v_len;
    SELECT date     FROM tempday WHERE id=1 INTO v_datemax;

    -- 5周内最低价日
    SELECT id,date,close,low FROM tempday WHERE id<=25 order by low asc LIMIT 1 
                                 INTO v_id,v_date2,v_close,v_low;

    -- 过滤停牌很久的个股? 只9jian才过滤
    -- IF DATE_ADD(v_datemax, INTERVAL 5 DAY) < @END THEN LEAVE tag_6mai; END IF;

    lbl_upto_100: WHILE v_id <= @v_len DO
        SELECT volume,amount FROM tempday WHERE id=(v_id) INTO v_volume,v_amount;

        SET v_sumvolume = v_sumvolume + v_volume;
        SET v_sumamount = v_sumamount + v_amount;

        -- upto 100% turnover
        IF  v_sumvolume >= v_shares0 THEN 
            SELECT date,yesc FROM tempday WHERE id=(v_id) INTO v_date1,v_open;
            SET v_avrg = (v_sumamount/v_sumvolume);
            SET v_chng = 100*(v_close-v_open)/v_open;
            SET v_turnov = 100*v_sumvolume/v_shares;
            -- SET v_wchng = 100*(v_close-v_avrg)/v_avrg;
            -- SELECT * FROM tempday;
            -- SELECT v_id;
            INSERT INTO tbl_6mai(code,date1,date2,off,open,low,close,
                            amount,volume,turnov,avrg,chng)
                     VALUES(a_code,v_date1,v_date2,v_id,v_open,v_low,v_close,
                            v_sumamount,v_sumvolume,v_turnov, v_avrg, v_chng);
            LEAVE lbl_upto_100; 
        END IF;

        SET v_id = v_id + 1;
    END WHILE lbl_upto_100;
END tag_6mai //

DROP PROCEDURE IF EXISTS sp_mavol5B25//
CREATE PROCEDURE sp_mavol5B25(a_code INT(6) ZEROFILL) tag_mavol5B25:BEGIN
    DECLARE v_close    DECIMAL(6,2)  DEFAULT 0;
    DECLARE v_vol      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_ma5      DECIMAL(6,2)  DEFAULT 0;
    DECLARE v_vol5     DECIMAL(12,2) DEFAULT 0;
    DECLARE v_ma13     DECIMAL(6,2)  DEFAULT 0;
    DECLARE v_vol13    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_ma25     DECIMAL(6,2)  DEFAULT 0;
    DECLARE v_vol25    DECIMAL(12,2) DEFAULT 0;

    call sp_create_tempday();

    INSERT INTO tempday(code,date,close,volume,amount) 
        SELECT code,date,close,volume,amount FROM day 
        WHERE code=a_code and date<=@END ORDER by date DESC LIMIT 25;

    -- 13 34 55 100
    SELECT count(*) FROM tempday INTO @v_len;
    SELECT close,volume FROM tempday WHERE id=1 INTO v_close,v_vol;

    IF @v_len < 25 THEN LEAVE tag_mavol5B25; END IF;

    -- ma 即有平均的意义，但vol没有
    SELECT SUM(amount)/SUM(volume), SUM(volume) FROM tempday WHERE id<=5 INTO v_ma5,  v_vol5;
    SELECT SUM(amount)/SUM(volume), SUM(volume) FROM tempday WHERE id<14 INTO v_ma13, v_vol13;
    SELECT SUM(amount)/SUM(volume), SUM(volume) FROM tempday WHERE id<26 INTO v_ma25, v_vol25;

    INSERT INTO tbl_mavol5B25(code,  close,   ma5,   ma13,  ma25,   vol,   vol5,   vol13,  vol25)
                     VALUES(a_code,v_close, v_ma5, v_ma13,v_ma25, v_vol, v_vol5, v_vol13,v_vol25);
END tag_mavol5B25 //

-- 考虑使用ma34代替ma34
DROP PROCEDURE IF EXISTS sp_ma5B25//
CREATE PROCEDURE sp_ma5B25(a_code INT(6) ZEROFILL) tag_ma5B25:BEGIN
    DECLARE v_date     DATE;
    DECLARE v_close    DECIMAL(6,2) DEFAULT 0;
    DECLARE v_ma5      DECIMAL(6,2) DEFAULT 0;
    DECLARE v_ma13     DECIMAL(6,2) DEFAULT 0;
    DECLARE v_ma25     DECIMAL(6,2) DEFAULT 0;

    call sp_create_tempday();

    INSERT INTO tempday(code,date,close) 
        SELECT code,date,close FROM day 
            WHERE code=a_code and date<=@END ORDER by date DESC LIMIT 25;

    SELECT count(*)   FROM tempday INTO @v_len;
    SELECT date,close FROM tempday WHERE id=1 INTO v_date,v_close;

    -- IF @v_len < 240 THEN LEAVE tag_ma60x240; END IF;
    IF @v_len = 25 THEN 
        SELECT SUM(close)/5    FROM tempday WHERE id<=5   INTO v_ma5  ;
        SELECT SUM(close)/13   FROM tempday WHERE id<=13  INTO v_ma13 ;
        SELECT SUM(close)/25   FROM tempday WHERE id<=25  INTO v_ma25 ;
        UPDATE tbl_ma240 SET date=v_date,close=v_close,
               ma5=v_ma5, ma13=v_ma13, ma25=v_ma25 WHERE code=a_code;
    END IF;
END tag_ma5B25 //

DROP PROCEDURE IF EXISTS sp_ma60x240//
CREATE PROCEDURE sp_ma60x240(a_code INT(6) ZEROFILL) tag_ma60x240:BEGIN
    DECLARE v_date     DATE;
    DECLARE v_close    DECIMAL(6,2) DEFAULT 0;
    DECLARE v_ma5      DECIMAL(6,3) DEFAULT 0;
    DECLARE v_ma13     DECIMAL(6,3) DEFAULT 0.001;
    DECLARE v_ma25     DECIMAL(6,3) DEFAULT 0.001;
    DECLARE v_ma60     DECIMAL(6,3) DEFAULT 0;
    DECLARE v_ma120    DECIMAL(6,3) DEFAULT 0.001;
    DECLARE v_ma240    DECIMAL(6,3) DEFAULT 0;

    call sp_create_tempday();

    -- SELECT date FROM day 
    --     WHERE code=a_code and date<=@END ORDER BY date DESC limit 240,1 INTO @START;

    INSERT INTO tempday(code,date,close) 
        SELECT code,date,close FROM day 
            WHERE code=a_code and date<=@END ORDER by date DESC LIMIT 240;

    SELECT count(*)   FROM tempday INTO @v_len;
    SELECT date,close FROM tempday WHERE id=1 INTO v_date,v_close;

    -- IF @v_len < 240 THEN LEAVE tag_ma60x240; END IF;
    IF @v_len >= 25 THEN 
        SELECT SUM(close)/5    FROM tempday WHERE id<=5   INTO v_ma5  ;
        SELECT SUM(close)/13   FROM tempday WHERE id<=13  INTO v_ma13 ;
        SELECT SUM(close)/25   FROM tempday WHERE id<=25  INTO v_ma25 ;
    END IF;

    IF @v_len >= 120 THEN 
        SELECT SUM(close)/60   FROM tempday WHERE id<=60  INTO v_ma60 ;
        SELECT SUM(close)/120  FROM tempday WHERE id<=120 INTO v_ma120;
    END IF;
    IF @v_len >= 240 THEN 
        SELECT SUM(close)/240  FROM tempday WHERE id<=240 INTO v_ma240;
    END IF;

    -- SELECT v_ma60, v_ma120, v_ma240;

    INSERT INTO tbl_ma240 (code,     date,  close,  ma5,  ma13,  ma25,  ma60,   ma120,   ma240)
                    VALUES(a_code, v_date,v_close,v_ma5,v_ma13,v_ma25,v_ma60, v_ma120, v_ma240);
END tag_ma60x240 //

DROP PROCEDURE IF EXISTS sp_stat_linqi//
CREATE PROCEDURE sp_stat_linqi() tag_stat_linqi:BEGIN
    DECLARE v_membs INT; 
    DECLARE v_len   INT; /* CURSOR and HANDLER declare in end of declaration */
    DECLARE v_id    INT DEFAULT 1; 
    DECLARE v_date  date DEFAULT 0; 
    DECLARE v_yesc  DECIMAL(6,2) DEFAULT 1000;
    DECLARE v_open  DECIMAL(6,2) DEFAULT 0;
    DECLARE v_close DECIMAL(6,2) DEFAULT 0;
    DECLARE v_high  DECIMAL(6,2) DEFAULT 0;
    DECLARE v_low   DECIMAL(6,2) DEFAULT 0;

    DROP TABLE IF EXISTS dlinqi;                /* open days */
    CREATE TABLE dlinqi (
        id          INT(6) PRIMARY key AUTO_INCREMENT NOT NULL,
        date        date NOT NULL,
        INDEX(date)
    );

    DROP   TABLE IF EXISTS ilinqi;    /* index of linqi */
    CREATE TABLE ilinqi (
        id          INT PRIMARY key AUTO_INCREMENT NOT NULL,
        date        date NOT NULL,
        yesc        DECIMAL(6,2) NOT NULL,
        open        DECIMAL(6,2) NOT NULL,
        high        DECIMAL(6,2) NOT NULL,
        low         DECIMAL(6,2) NOT NULL,
        close       DECIMAL(6,2) NOT NULL,
        INDEX(date)
    );

    SET @start_linqi = '2014-08-01';
    call sp_create_tempday();
    INSERT INTO tempday(code,date,yesc,open,high,low,close,volume)
        SELECT d.code,d.date,yesc,open,high,low,close,volume FROM day as d,linqi as l 
        WHERE d.date >= @start_linqi and d.code = l.code;
    INSERT INTO dlinqi (date) SELECT date from day WHERE code = 900001 and date>=@start_linqi;

    SELECT max(id)   FROM dlinqi INTO v_len;
    SELECT count(*)  FROM linqi  INTO v_membs;

    SELECT v_len;
    # SELECT * from tempday;

    WHILE v_id <= v_len DO
        SELECT date FROM dlinqi WHERE id=(v_id) INTO v_date;
        SELECT (sum( open/yesc)+(v_membs-count(*)))/v_membs*v_yesc FROM tempday WHERE date=v_date INTO v_open;
        SELECT (sum(close/yesc)+(v_membs-count(*)))/v_membs*v_yesc FROM tempday WHERE date=v_date INTO v_close;
        SELECT (sum( high/yesc)+(v_membs-count(*)))/v_membs*v_yesc FROM tempday WHERE date=v_date INTO v_high;
        SELECT (sum( low /yesc)+(v_membs-count(*)))/v_membs*v_yesc FROM tempday WHERE date=v_date INTO v_low;
        INSERT INTO ilinqi (date,  yesc, open,  high, low, close)
                    VALUES(v_date,v_yesc, v_open, v_high,v_low,v_close);
        SET v_yesc = v_close;
        SET v_id = v_id + 1;
    END WHILE;

END tag_stat_linqi //

-- 一些需要与shell通信的系统变量

    SET @fn_flt_kdj_up          = 1;   
    SET @fn_mavol5B25           = 5;
    SET @fn_ma5B25              = 7;
    SET @fn_ma60x2x4            = 9;
    SET @fn_dugu9jian           = 10;
    SET @fn_6maishenjian        = 11;
    SET @fn_taox_ratio          = 12;
    SET @fn_fbi_ratio           = 13;
    SET @FORCE                  = 0;    -- 1时强制计算过滤停牌很久的个股
    SET @START      = '2013-12-6';
    SET @END        = '2014-11-26';
    SET @NUM        = 240;
    SET @NMC_RATIO  = 1;
    
-- 若要计算3日，argv_n为3

    SET @argv_change = 12;
    SET @argv_n = 3;

-- 每个SP中创建一个指定的私用表，如此，则只要在SP开头使用一次EXECUTE语句就可以了
-- 每个SP都有两个参数，一个表作为输入，一个code做为另一个输入

--  THIS EXECUTE DELIMITER

--  call sp_macd('day', 2);
--  call sp_kdj('day', 2, 9);
--  call sp_filter_kdj('cap');
--  call sp_kdj_wk('day', 750, 9);
--  call sp_7day('day', 750);

--  call sp_day('day', 750);
--  call sp_xRD();

--  call sp_stat_linqi();
--  call sp_get_down_turnov(2);
--  call sp_visit_tbl('cap', @fn_dugu9jian);
--  call sp_visit_tbl('cap', @fn_6maishenjian);
    call sp_visit_tbl('zxg', @fn_taox_ratio);
