import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

class VistaResumenPorProducto extends StatefulWidget {
  const VistaResumenPorProducto({Key? key}) : super(key: key);

  @override
  _VistaResumenPorProductoState createState() => _VistaResumenPorProductoState();
}

class _VistaResumenPorProductoState extends State<VistaResumenPorProducto> {
  List<Map<String, dynamic>> _productosConsolidados = [];
  bool _cargando = true;
  double _totalGeneral = 0.0;
  int _totalUnidades = 0;

  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  @override
  void initState() {
    super.initState();
    // Por defecto inicia desde el primer día del mes actual hasta hoy
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = ahora;
    _cargarResumenProductos();
  }

  Future<Database> _obtenerBaseDatos() async {
    final path = await getDatabasesPath();
    final dbPath = '$path/app_ventas.db';
    return openDatabase(dbPath);
  }

  Future<void> _cargarResumenProductos() async {
    setState(() => _cargando = true);
    try {
      final db = await _obtenerBaseDatos();

      // 1. Verificar tablas existentes en SQLite
      final tablesResult = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tablesResult.map((t) => t['name'].toString()).toList();

      Map<String, Map<String, dynamic>> resumenMap = {};

      String? tablaDetalles = tableNames.firstWhere(
        (t) => t == 'detalle_pedidos' || t == 'detalles_pedido' || t == 'items_pedido',
        orElse: () => '',
      );

      // CASO A: Si existe tabla de detalles relacional
      if (tablaDetalles.isNotEmpty) {
        final List<Map<String, dynamic>> resultado = await db.rawQuery('''
          SELECT 
            nombre_producto,
            SUM(cantidad) as total_cantidad,
            SUM(subtotal) as total_monto
          FROM $tablaDetalles
          GROUP BY nombre_producto
          ORDER BY total_cantidad DESC
        ''');

        for (var item in resultado) {
          String nombre = item['nombre_producto']?.toString() ?? 'Producto';
          int cant = (item['total_cantidad'] as num? ?? 0).toInt();
          double monto = (item['total_monto'] as num? ?? 0).toDouble();

          resumenMap[nombre] = {
            'nombre_producto': nombre,
            'total_cantidad': cant,
            'total_monto': monto,
          };
        }
      } 
      // CASO B: Si los pedidos guardan sus productos internamente (JSON / Lista)
      else if (tableNames.contains('pedidos')) {
        final pragma = await db.rawQuery("PRAGMA table_info(pedidos)");
        final columns = pragma.map((c) => c['name'].toString()).toList();

        String? colFecha = columns.contains('fecha') 
            ? 'fecha' 
            : (columns.contains('fecha_creacion') ? 'fecha_creacion' : null);

        String query = "SELECT * FROM pedidos";
        List<dynamic> args = [];

        if (colFecha != null) {
          List<String> whereClauses = [];
          if (_fechaInicio != null) {
            whereClauses.add("$colFecha >= ?");
            args.add(DateFormat('yyyy-MM-dd').format(_fechaInicio!));
          }
          if (_fechaFin != null) {
            whereClauses.add("$colFecha <= ?");
            args.add("${DateFormat('yyyy-MM-dd').format(_fechaFin!)} 23:59:59");
          }
          if (whereClauses.isNotEmpty) {
            query += " WHERE " + whereClauses.join(" AND ");
          }
        }

        final List<Map<String, dynamic>> pedidos = await db.rawQuery(query, args);

        String? colItems;
        for (var col in ['productos', 'detalles', 'items', 'detalle', 'lista_productos', 'carrito']) {
          if (columns.contains(col)) {
            colItems = col;
            break;
          }
        }

        for (var p in pedidos) {
          if (colItems != null && p[colItems] != null) {
            try {
              var itemsRaw = p[colItems];
              List<dynamic> listItems = [];
              if (itemsRaw is String) {
                listItems = jsonDecode(itemsRaw);
              } else if (itemsRaw is List) {
                listItems = itemsRaw;
              }

              for (var item in listItems) {
                String nombre = (item['nombre'] ?? item['nombre_producto'] ?? item['producto'] ?? item['titulo'] ?? 'Producto').toString();
                int cant = int.tryParse(item['cantidad']?.toString() ?? '1') ?? 1;
                double precio = double.tryParse(item['precio']?.toString() ?? item['precio_unitario']?.toString() ?? '0') ?? 0.0;
                double subtotal = double.tryParse(item['subtotal']?.toString() ?? '0') ?? (cant * precio);

                if (!resumenMap.containsKey(nombre)) {
                  resumenMap[nombre] = {
                    'nombre_producto': nombre,
                    'total_cantidad': 0,
                    'total_monto': 0.0,
                  };
                }
                resumenMap[nombre]!['total_cantidad'] = (resumenMap[nombre]!['total_cantidad'] as int) + cant;
                resumenMap[nombre]!['total_monto'] = (resumenMap[nombre]!['total_monto'] as double) + subtotal;
              }
            } catch (e) {
              debugPrint("Error decodificando productos del pedido: $e");
            }
          }
        }
      }

      List<Map<String, dynamic>> resultado = resumenMap.values.toList();
      resultado.sort((a, b) => (b['total_cantidad'] as int).compareTo(a['total_cantidad'] as int));

      double sumaMonto = 0.0;
      int sumaCantidad = 0;
      for (var item in resultado) {
        sumaCantidad += (item['total_cantidad'] as int);
        sumaMonto += (item['total_monto'] as double);
      }

      setState(() {
        _productosConsolidados = resultado;
        _totalUnidades = sumaCantidad;
        _totalGeneral = sumaMonto;
        _cargando = false;
      });
    } catch (e) {
      debugPrint("Error cargando resumen: $e");
      setState(() => _cargando = false);
    }
  }

  Future<void> _seleccionarFechaInicio(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicio ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && picked != _fechaInicio) {
      setState(() {
        _fechaInicio = picked;
      });
      _cargarResumenProductos();
    }
  }

  Future<void> _seleccionarFechaFin(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaFin ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && picked != _fechaFin) {
      setState(() {
        _fechaFin = picked;
      });
      _cargarResumenProductos();
    }
  }

  Future<void> _generarPdfResumen() async {
    final pdf = pw.Document();
    final formatoMoneda = NumberFormat.currency(symbol: 'L ', decimalDigits: 2);
    final fechaHoy = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    String rangoTexto = "Todas las fechas";
    if (_fechaInicio != null && _fechaFin != null) {
      rangoTexto = "${DateFormat('dd/MM/yyyy').format(_fechaInicio!)} al ${DateFormat('dd/MM/yyyy').format(_fechaFin!)}";
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Reporte Resumen por Producto',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text(fechaHoy, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text('Rango de Fechas: $rangoTexto', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('Total Unidades: $_totalUnidades'),
            pw.Text('Monto Total: ${formatoMoneda.format(_totalGeneral)}'),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Producto', 'Cant. Total', 'Monto Total'],
              data: _productosConsolidados.map((p) {
                final nombre = p['nombre_producto']?.toString() ?? 'Sin nombre';
                final cant = (p['total_cantidad'] as num? ?? 0).toInt();
                final monto = (p['total_monto'] as num? ?? 0).toDouble();
                return [nombre, '$cant', formatoMoneda.format(monto)];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Resumen_Por_Producto.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatoMoneda = NumberFormat.currency(symbol: 'L ', decimalDigits: 2);
    final formatoFecha = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen por Producto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _productosConsolidados.isEmpty ? null : _generarPdfResumen,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarResumenProductos,
          ),
        ],
      ),
      body: Column(
        children: [
          // Selector de Rango de Fechas
          Card(
            margin: const EdgeInsets.all(10),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filtrar por Período / Semana:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _seleccionarFechaInicio(context),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            _fechaInicio != null ? 'Desde: ${formatoFecha.format(_fechaInicio!)}' : 'Fecha Inicio',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _seleccionarFechaFin(context),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            _fechaFin != null ? 'Hasta: ${formatoFecha.format(_fechaFin!)}' : 'Fecha Fin',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Resumen de Totales
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Total Unidades', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('$_totalUnidades', style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Monto Total', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(formatoMoneda.format(_totalGeneral), style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          // Lista de Productos Consolidados
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _productosConsolidados.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'No hay productos registrados en los pedidos para las fechas seleccionadas.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _productosConsolidados.length,
                        itemBuilder: (context, index) {
                          final item = _productosConsolidados[index];
                          final nombre = item['nombre_producto'] ?? 'Producto';
                          final cant = item['total_cantidad'] ?? 0;
                          final monto = item['total_monto'] ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).primaryColor,
                                child: Text('$cant', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Total unidades: $cant'),
                              trailing: Text(
                                formatoMoneda.format(monto),
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
