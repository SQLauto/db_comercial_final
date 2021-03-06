USE [db_comercial_final]
GO
-- =============================================
-- Author:		Laurence Saavedra
-- Create date: 201103
-- Modificado:	2012-10
-- Description:	Convertir la unidad de la transacci�n a unidad de medida del almac�n para el art�culo. 
--              Afectar inv_movimientos. 
--              Toma la decisi�n de c�mo crear capas o referenciar capas existentes. 
--              Decide como hacer movimientos en cuanto a series. 
--              Actualiza el costo del movimiento que genera la salida. 
--              Actualiza informaci�n de costo promedio y �ltimo costo en ew_articulos_sucursales.
-- =============================================
ALTER TRIGGER [dbo].[tg_inv_transacciones_mov_i]
   ON  [dbo].[ew_inv_transacciones_mov]
   AFTER INSERT
AS 

SET NOCOUNT ON;

DECLARE 	
	@comentario			VARCHAR(4000),
	@idtran				INT,
	@idr				INT,
	@fecha				SMALLDATETIME,
	@transaccion		VARCHAR(5),
	@folio				VARCHAR(15),
	@referencia			VARCHAR(25),
	@idalmacen			SMALLINT,
	@consecutivo		SMALLINT,
	@idcapa				BIGINT,
	@idpedimento		BIGINT,
	@tipo				TINYINT,
	@idarticulo INT,
	@cantidad			DECIMAL(15,4),
	@costo				DECIMAL(15,4),
	@costo2				DECIMAL(15,4),
	@afectainv			BIT,
	@invafectado		BIT,
	@series				VARCHAR(4000),
	@lote				VARCHAR(25),
	@fecha_caducidad	SMALLDATETIME,
	@maneja_series		BIT,
	@maneja_pedimentos  BIT,
	@maneja_lotes		BIT,
	@caduca				BIT,
	@usuario			SMALLINT,
	@inventariable		BIT,
	@idum				SMALLINT,
	@factor				DECIMAL(15,4),
	@idum_almacen		SMALLINT,
	@factor_almacen		DECIMAL(15,4),
	@afectaref			BIT,
	@tablaref			VARCHAR(30),
	@idtran2			BIGINT,
	@idmov2				MONEY,
	@msg				VARCHAR(200),
	@cont				SMALLINT,
	@cont2				SMALLINT,
	@comando			VARCHAR(4000),
	@cant				DECIMAL(15,4),
	@cantidad2			DECIMAL(15,4),
	@existenciaLote		DECIMAL(15,4),
	@importe			DECIMAL(15,4),
	@importe2			DECIMAL(15,4),
	@ximporte			DECIMAL(15,4),
	@ximporte2			DECIMAL(15,4),
	@yimporte			DECIMAL(15,4),
	@yimporte2			DECIMAL(15,4),
	@serie				VARCHAR(100)
	,@idmov				MONEY
	,@idr2				INT
	,@actualizarCosto	BIT
	,@b					BIT
	,@codarticulo		VARCHAR(50)
	
--Datos para actualizaci�n de costo
DECLARE
	@itm_costo AS DECIMAL(12,2),
	@itm_costo2 AS DECIMAL(12,2),
	@idconcepto SMALLINT,
	@costo_u AS DECIMAL(18,6)

SELECT @msg = ''



DECLARE cur_inv_transacciones_mov_i CURSOR FOR
	SELECT
		a.idtran, b.idr, a.fecha, a.transaccion, a.folio, a.referencia, a.idalmacen, a.idtran2, a.idu, 
		b.idr, b.afectaref, b.tablaref, b.idmov2, b.idpedimento, b.idcapa, b.afectainv, b.invafectado, 
		b.consecutivo, b.tipo,  b.idalmacen, b.idarticulo, b.cantidad, b.costo, b.costo2, b.lote, b.fecha_caducidad, 
		b.idum, e.factor, d.idum_almacen, f.factor, d.series, d.pedimento, d.lotes, itm.idmov, d.codigo, a.idconcepto
	FROM 
		inserted AS b 
		LEFT JOIN ew_inv_transacciones AS a ON a.idtran = b.idtran
		LEFT JOIN ew_inv_almacenes AS c ON c.idalmacen = a.idalmacen
		LEFT JOIN ew_articulos AS d ON d.idarticulo = b.idarticulo
		LEFT JOIN ew_cat_unidadesMedida AS e ON e.idum = b.idum
		LEFT JOIN ew_cat_unidadesMedida AS f ON f.idum = d.idum_almacen
		LEFT JOIN ew_inv_transacciones_mov itm ON itm.idr=b.idr
		LEFT JOIN ew_inv_capas ic ON ic.idcapa=b.idcapa
	WHERE 
		d.inventariable = 1

OPEN cur_inv_transacciones_mov_i

FETCH NEXT FROM cur_inv_transacciones_mov_i INTO
	@idtran, @idr, @fecha, @transaccion, @folio, @referencia, @idalmacen, @idtran2, @usuario, 
	@idr, @afectaref, @tablaref, @idmov2, @idpedimento, @idcapa, @afectainv, @invafectado, 
	@consecutivo, @tipo,  @idalmacen, @idarticulo, @cant, @costo, @costo2, @lote, @fecha_caducidad, 
	@idum, @factor, @idum_almacen, @factor_almacen, @maneja_series, @maneja_pedimentos, @maneja_lotes, @idmov,@codarticulo
	,@idconcepto

WHILE @@fetch_status = 0
BEGIN
	IF @usuario IS NULL
	BEGIN
		SELECT @usuario = dbo._sys_fnc_usuario()
	END

	IF @idtran IS NULL
	BEGIN
		CLOSE cur_inv_transacciones_mov_i
		DEALLOCATE cur_inv_transacciones_mov_i
		
		RAISERROR('Error: El identificador de transacci�n es nulo..', 16, 1)
		RETURN
	END
	
	IF @factor_almacen IS NULL OR @factor_almacen = 0
	BEGIN
		SET @factor_almacen = 1
	END
	
	IF @factor IS NULL OR @factor = 0
	BEGIN
		SET @factor = @factor_almacen
	END
	
	-- Convirtiendo las unidades de entrada en unidades de almacen
	SET @cantidad = ROUND(@cant * (@factor / @factor_almacen), 6)
	
	IF @maneja_pedimentos = '1' AND @idpedimento = 0
	BEGIN
		SELECT @idpedimento = 1
	END
	--PRINT('1')
	-- Afectando el kardex, para aquellos que la cantidad sea mayor a 0
	IF @afectainv = '1' AND @invafectado = '0' AND @tipo IN (1,2) AND @cantidad > 0
	BEGIN
		SELECT @b=0, @actualizarCosto=0

		-------------------------------------------------------------------------------
		-- 1) ENTRADA � SALIDA. La capa ha sido indicada
		-------------------------------------------------------------------------------
		IF @idcapa>0 AND @afectaref=0
		BEGIN
			---------------------------------------------------------------------------
			-- Modificacion hecha Oct 2012 para la existencia x Lote
			---------------------------------------------------------------------------
			IF @tipo=2 AND @maneja_lotes=1
			BEGIN
				SELECT @existenciaLote=0
				SELECT @existenciaLote=ISNULL(SUM(cantidad),0) FROM [dbo].[fn_inv_capasSalidaLote] (@idalmacen,@idarticulo,@cantidad,@lote,@idcapa)
				IF @existenciaLote<@cantidad
				BEGIN
					SELECT @msg='Articulo: [' + @codarticulo + '] Lote=[' + @lote + ']  Existencia=' + CONVERT(VARCHAR(15),@existenciaLote) + '  / Salida='+ CONVERT(VARCHAR(15),@cantidad) 
					BREAK
				END
			
				INSERT INTO ew_inv_movimientos
					(idr2, idtran, idconcepto, idpedimento, consecutivo, idcapa, idalmacen, fecha, 
					transaccion, folio, referencia, codigo, tipo, idarticulo, 
					cantidad, costo, costo2, usuario, comentario, idmov2)				
				SELECT
					0, @idtran, @idconcepto, @idpedimento,   @consecutivo, cs.idcapa, @idalmacen, @fecha, 
					@transaccion, @folio, @referencia, '', @tipo, @idarticulo, 
					cs.cantidad, cs.costo, cs.costo2, @usuario, '',@idmov
				FROM
					dbo.fn_inv_capasSalidaLote(@idalmacen, @idarticulo, @cantidad, @lote, @idcapa) cs
					LEFT JOIN ew_inv_capas ic ON ic.idcapa=cs.idcapa	
			END
			ELSE
			BEGIN
				
				INSERT INTO ew_inv_movimientos
					(idr2, idtran, idconcepto, idpedimento, consecutivo, idcapa, idalmacen, fecha, 
					transaccion, folio, referencia, codigo, tipo, idarticulo, 
					cantidad, costo, costo2, usuario, comentario, idmov2)				
				VALUES 
					(0, @idtran, @idconcepto, @idpedimento, @consecutivo, @idcapa, @idalmacen, @fecha, 
					@transaccion, @folio, @referencia, '', @tipo, @idarticulo, 
					@cantidad, @costo, @costo2, @usuario, '',@idmov)			
			END
			SELECT @b=1, @actualizarCosto=(CASE WHEN @tipo=2 THEN 1 ELSE 0 END)
			IF @tipo=1 AND @costo=0 SELECT @actualizarCosto=1
		END
			
		-------------------------------------------------------------------------------
		-- 2) ENTRADA � SALIDA. Referencia a un movimiento previo en el kardex
		-------------------------------------------------------------------------------
			
		IF (@b=0) AND (@maneja_series=0) AND (@idmov2>0) AND (@afectaref='1') 
		BEGIN 
			SELECT TOP 1 @idr2=idr FROM	ew_inv_movimientos WHERE idmov2=@idmov2 ORDER BY idr DESC
			IF @idr2 IS NULL
			BEGIN
				SELECT @msg = 'Error. la referencia al kardex no es correcta para el articulo: ' + @codarticulo
				BREAK			
			END
			-- <BEGIN> Cambios Laurence Saavedra Octubre 2012
			INSERT INTO ew_inv_movimientos 
				(idr2, idtran, idconcepto, idpedimento, consecutivo, idcapa, idalmacen, fecha, 
				transaccion, folio, referencia, codigo, tipo, idarticulo, 
				cantidad, costo, costo2, usuario, comentario, idmov2)	
			SELECT
				im.idr, @idtran, @idconcepto, @idpedimento, im.consecutivo, (CASE WHEN im.idcapa>0 THEN imc.idcapa ELSE (-1) END), @idalmacen, @fecha,
				@transaccion, @folio, @referencia, '', @tipo, @idarticulo, 
				imc.cantidad, imc.costo, imc.costo2, @usuario, '',@idmov				
			FROM
				dbo.fn_inv_capasPorIDMOV(@idmov2,@cantidad) imc
				LEFT JOIN ew_inv_movimientos im ON im.idr=imc.idr
			WHERE 
				im.idmov2=@idmov2
			-- <END> Cambios Laurence Saavedra Octubre 2012
			/*
			VALUES 
				(@idr2, @idtran, @idconcepto, @idpedimento, @consecutivo, (-1), @idalmacen, @fecha, 
				@transaccion, @folio, @referencia, '', @tipo, @idarticulo, 
				@cantidad, @costo, @costo2, @usuario, '',@idmov)				
			*/
			SELECT @b=1, @actualizarCosto=1   --(CASE WHEN @tipo=2 THEN 1 ELSE 0 END)
			--PRINT('3a')
		END			
			
		-------------------------------------------------------------------------------
		-- 3) ENTRADA. Maneja Series
		-------------------------------------------------------------------------------
		IF (@b=0) AND (@tipo=1) AND (@maneja_series=1)
		BEGIN 
			SELECT @series = CONVERT(VARCHAR(4000), series) FROM ew_inv_transacciones_mov WHERE	idr=@idr
			
			IF @series IS NULL OR LEN(@series) = 0
			BEGIN
				SELECT @msg = 'Error. no se especific� ningun no. de serie (inv_transacciones_mov.series) para el articulo: ' + @codarticulo
				BREAK
			END
			
			SELECT @cont = 0
			SELECT @cont = COUNT(*) FROM dbo._sys_fnc_series(@series)
			--PRINT @cont
			--PRINT @cantidad
			
			IF @cont!=@cantidad 
			BEGIN
				SELECT @msg = 'Error. no se especificaron todos los no. de serie (inv_transacciones_mov.series) para el articulo: ' + @codarticulo
				BREAK
			END
			
			SELECT @ximporte = @costo
			SELECT @ximporte2 = @costo2
			SELECT @cont2 = 0
			
			DECLARE cur_tg_detalle_provee_i2 CURSOR FOR
				SELECT 
					serie 
				FROM dbo._sys_fnc_series(@series)
			OPEN cur_tg_detalle_provee_i2
			FETCH NEXT FROM cur_tg_detalle_provee_i2 INTO 
				@serie
			WHILE @@fetch_status = 0
			BEGIN
				SELECT @idcapa = 0
				SELECT @yimporte = 0
				SELECT @yimporte2 = 0
				SELECT @cont2 = @cont2 + 1
				
				IF @cont2 = @cont
				BEGIN
					SELECT @yimporte = @ximporte
					SELECT @yimporte2 = @ximporte2
				END
					ELSE
				BEGIN
					SELECT @yimporte = ROUND(@costo / @cantidad, 2)
					SELECT @yimporte2 = ROUND(@costo2 / @cantidad, 2)
				END
				--PRINT('4')
				-- Creamos una capa por cada serie, si existe la capa con existencia=0 toma ese numero IDCAPA
				EXEC _inv_prc_capasCrear @idcapa OUTPUT,@idtran,@folio,@fecha,@idarticulo,@serie,1,@yimporte,@yimporte2,@lote,@fecha_caducidad,''
				--PRINT('5')
				IF @idcapa IS NULL or @idcapa < 1
				BEGIN
					SELECT @msg = 'Error al intentar crear la capa de costos (SP: _ALM_CAPAS_CREAR.) para el articulo: ' + @codarticulo
					BREAK
				END
				
				-- Realizamos el movimiento en el almacen
				--PRINT('6')
				INSERT INTO ew_inv_movimientos 
					(idtran, idconcepto, idpedimento, consecutivo, idcapa, idalmacen, fecha, 
					transaccion, folio, referencia, codigo, tipo, idarticulo, 
					cantidad, costo, costo2, usuario, comentario,idmov2)
				VALUES 
					(@idtran, @idconcepto, @idpedimento, @consecutivo, @idcapa, @idalmacen, @fecha, 
					@transaccion, @folio, @referencia, '',  1, @idarticulo, 
					1, @yimporte, @yimporte2, @usuario, '',@idmov)
				
				SELECT @ximporte = @ximporte - @yimporte
				SELECT @ximporte2 = @ximporte2 - @yimporte2
				
				FETCH NEXT FROM cur_tg_detalle_provee_i2 INTO 
					@serie
			END
			CLOSE cur_tg_detalle_provee_i2
			DEALLOCATE cur_tg_detalle_provee_i2
			SELECT @b=1
		END
			
		-------------------------------------------------------------------------------
		-- 4) SALIDA. Maneja Series
		-------------------------------------------------------------------------------			
		IF (@b=0) AND (@tipo=2) AND (@maneja_series=1)
		BEGIN
			-- Validar series
			SELECT 
				@series = CONVERT(VARCHAR(4000), series) 
			FROM 
				ew_inv_transacciones_mov 
			WHERE 
				idr = @idr
			
			IF @series IS NULL OR LEN(@series) = 0
			BEGIN
				SELECT @msg = 'Error. no se especific� ningun no. de serie (inv_transacciones_mov.series) para el articulo: ' + @codarticulo
				BREAK
			END
			SELECT @cont = 0
			SELECT @cont = COUNT(*) FROM dbo._sys_fnc_series(@series)
			IF @cont < @cantidad
			BEGIN
				SELECT @msg = 'Error. no se especificaron todos los no. de serie (inv_transacciones_mov.series) para el articulo: ' + @codarticulo
				BREAK
			END
			DECLARE cur_tg_detalle_provee_i2 CURSOR FOR
				SELECT 
					serie 
				FROM dbo._sys_fnc_series(@series)
			
			OPEN cur_tg_detalle_provee_i2
			
			FETCH NEXT FROM cur_tg_detalle_provee_i2 INTO 
				@serie
			
			WHILE @@fetch_status = 0
			BEGIN
				SELECT 
					@idcapa = ic.idcapa
				FROM 
					ew_inv_capas AS ic
				WHERE
					ic.existencia > 0
					AND ic.serie = @serie
					AND ic.idarticulo = @idarticulo
				IF @idcapa IS NULL OR @idcapa = 0
				BEGIN
					SELECT @msg = 'Error: No se encontr� la serie [' + @serie + '], para el articulo: ' + @codarticulo
					BREAK
				END
					ELSE
				BEGIN
					INSERT INTO ew_inv_movimientos 
						(idr2, idtran, idconcepto, idpedimento, consecutivo, idcapa, idalmacen, fecha, 
						transaccion, folio, referencia, codigo, tipo, idarticulo, 
						cantidad, costo, costo2, usuario, comentario, idmov2)
					VALUES 
						(@idr, @idtran, @idconcepto, @idpedimento, @consecutivo, @idcapa, @idalmacen, @fecha, 
						@transaccion, @folio, @referencia, '', @tipo, @idarticulo, 
						1, @costo, @costo2, @usuario, '',@idmov)
						--PRINT('7')
				END
				
				FETCH NEXT FROM cur_tg_detalle_provee_i2 INTO 
					@serie
			END
			
			CLOSE cur_tg_detalle_provee_i2
			DEALLOCATE cur_tg_detalle_provee_i2
			SELECT @b=1, @actualizarCosto=1
		END			
			
		-------------------------------------------------------------------------------
		-- 5) ENTRADA � SALIDA. Otros
		-------------------------------------------------------------------------------
		IF (@b=0) 
		BEGIN
			SELECT @idcapa = 0
			IF @tipo=1
			BEGIN
				EXEC _inv_prc_capasCrear @idcapa OUTPUT,@idtran,@folio,@fecha,@idarticulo,'',@cantidad,@costo,@costo2,@lote,@fecha_caducidad,''	
				IF @idcapa IS NULL or @idcapa < 1
				BEGIN
					SELECT @msg = 'Error al intentar crear la capa de costos (SP: _ALM_CAPAS_CREAR) para el articulo: ' + @codarticulo
					BREAK
				END
			END
			ELSE
			BEGIN
				SELECT @actualizarCosto=1
			END
			
			--PRINT('8')
			-- Realizamos el movimiento en el almacen
			INSERT INTO ew_inv_movimientos 
				(idtran, idconcepto, idpedimento, consecutivo, idcapa, idalmacen, fecha, 
				transaccion, folio, referencia, codigo, tipo, idarticulo, 
				cantidad, costo, costo2, usuario, comentario,idmov2)
			VALUES 
				(@idtran, @idconcepto, @idpedimento, @consecutivo, @idcapa, @idalmacen, @fecha, 
				@transaccion, @folio,  @referencia , '', @tipo, @idarticulo, 
				@cantidad, @costo, @costo2, @usuario, '',@idmov)
			SELECT @b=1
		END
	
		-----------------------------------------------------------------------------------------------------------------
		--   ACTUALIZAR COSTO RESULTANTE EN ew_inv_transacciones_mov --
		-----------------------------------------------------------------------------------------------------------------
		IF (@actualizarCosto=1)
		BEGIN
			SELECT 
				@itm_costo = SUM(costo)
				,@itm_costo2 = SUM(costo2)
			FROM 
				ew_inv_movimientos
			WHERE 
				idtran = @idtran 
				AND idarticulo = @idarticulo
				AND idmov2=@idmov

			UPDATE ew_inv_transacciones_mov SET 
				costo = @itm_costo
				,costo2 = @itm_costo2
			WHERE 
				idr = @idr
			
			UPDATE ew_inv_transacciones SET
				total = (
					SELECT
						SUM(itm.costo)
					FROM ew_inv_transacciones_mov AS itm
					WHERE
						itm.idtran = @idtran
				)
			WHERE
				idtran = @idtran
		END

		-----------------------------------------------------------------------------------------
		--  ACTUALIZAR COSTOS EN CATALOGO
		-----------------------------------------------------------------------------------------
		IF @tipo = 1
		BEGIN
		--PRINT('9')
			SELECT @costo_u = (@costo / @cantidad)
			EXEC [dbo].[_inv_prc_ultimoCostoValidar] @idarticulo, @idalmacen, @costo_u

			UPDATE ew_articulos_almacenes SET
				costo_ultimo = (@costo / @cantidad)
				,costo_promedio = (
					SELECT
						CONVERT(DECIMAL(18,6), SUM(ice.costo) / SUM(ice.existencia))
					FROM 
						ew_inv_capas_existencia AS ice
						LEFT JOIN ew_inv_capas AS ic ON ic.idcapa = ice.idcapa
					WHERE
						ice.existencia > 0
						AND ic.idarticulo = @idarticulo
				)
			WHERE
				idarticulo = @idarticulo
				AND idalmacen = @idalmacen
			
			UPDATE ew_articulos_sucursales SET 
				costo_ultimo = (@costo / @cantidad)
				,costo_promedio = (
					SELECT
						CONVERT(DECIMAL(18,6), SUM(ice.costo) / SUM(ice.existencia))
					FROM 
						ew_inv_capas_existencia AS ice
						LEFT JOIN ew_inv_capas AS ic ON ic.idcapa = ice.idcapa
					WHERE
						ice.existencia > 0
						AND ic.idarticulo = @idarticulo
				)
			WHERE 
				idarticulo = @idarticulo
				AND idsucursal = (SELECt idsucursal FROM ew_inv_almacenes WHERE idalmacen = @idalmacen)
			
			-- Inicia Cambios Julio 2012
			IF @idconcepto=16
			BEGIN 
				IF @costo2=0 
					SELECT @costo2=@costo
				UPDATE ew_articulos_sucursales SET 
					--costo_base=(CASE WHEN costeo=2 THEN costo_ultimo ELSE costo_promedio END)
					costo_base=ROUND(@costo2/@cantidad,2)
				WHERE 
					idarticulo = @idarticulo
					AND idsucursal = (SELECt idsucursal FROM ew_inv_almacenes WHERE idalmacen = @idalmacen)
					AND costeo IN (1,2)
			END
			-- Finaliza Cambios Julio 2012 By Laurence 
			

		END
		-----------------------------------------------------------------------------------------
		--   ACTUALIZAR COSTO RESULTANTE EN suc_art  --
		-----------------------------------------------------------------------------------------
		-- Indicamos que ya realizamos el movimiento en almacen
		UPDATE ew_inv_transacciones_mov SET 
			invafectado = 1 
		WHERE 
			idr = @idr


		IF (@idmov2>0) AND (@afectaref='1')
		BEGIN
			INSERT INTO ew_sys_movimientos_acumula
				(idmov1, idmov2, campo, valor)
			VALUES
				(@idmov, @idmov2, 'surtido', @cantidad)
			
		END
				
		
	END
	
	-- Siguiente Registro
	FETCH NEXT FROM cur_inv_transacciones_mov_i INTO
		@idtran, @idr, @fecha, @transaccion, @folio, @referencia, @idalmacen, @idtran2, @usuario, 
		@idr, @afectaref, @tablaref, @idmov2, @idpedimento, @idcapa, @afectainv, @invafectado, 
		@consecutivo, @tipo,  @idalmacen, @idarticulo, @cant, @costo, @costo2, @lote, @fecha_caducidad, 
		@idum, @factor, @idum_almacen, @factor_almacen, @maneja_series, @maneja_pedimentos, @maneja_lotes, @idmov,@codarticulo
		,@idconcepto
END

CLOSE cur_inv_transacciones_mov_i
DEALLOCATE cur_inv_transacciones_mov_i

IF LEN(@msg) > 0 
BEGIN
	RAISERROR(@msg, 16, 1)
	RETURN
END
