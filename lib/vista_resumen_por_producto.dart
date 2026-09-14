//import 'dart:convert';
//import 'package:flutter/material.dart';
//import 'package:pdf/pdf.dart';
//import 'package:pdf/widgets.dart' as pw;
//import 'package:printing/printing.dart';
//import 'package:sqflite/sqflite.dart';
//import 'package:intl/intl.dart';

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
  String _mensajeDiagnostico = "";

  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  @override
  void initState() {
    super.initState();
    // Inicia por defecto cubriendo los últimos 30 días
    final ahora = DateTime.now();
    _fechaInicio = ahora.subtract(const Duration(days: 30));
    _fechaFin = ahora;
    _cargarResumenProductos();
  }

  Future<void> _cargarResumenProductos() async {
    setState(() {
      _cargando = true;
      _mensajeDiagnostico = "";
    });

    try {
      final path = await getDatabasesPath();
      final dbPath = '$path/app_ventas.db';
      final db = await openDatabase(dbPath);

      // Obtener todas las tablas en la base de datos SQLite
      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'"
      );
      List<String> tablas = tablesResult.map((t) => t['name'].toString()).toList();

      Map<String, Map<String, dynamic>> resumenMap = {};
      List<String> infoEstrucutra = [];

      for (String tabla in tablas) {
        final pragma = await db.rawQuery("PRAGMA table_info($tabla)");
        List<String> columnas = pragma.map((c) => c['name'].toString()).toList();
        infoEstrucutra.add("Tabla: '$tabla' -> [${columnas.join(', ')}]");

        final List<Map<String, dynamic>> filas = await db.query(tabla);

        for (var fila in filas) {
          // Evaluar filtro de fecha si la tabla tiene columna de fecha
          String? colFecha = columnas.firstWhere(
            (c) => c.toLowerCase().contains('fecha') || c.toLowerCase().contains('date'),
            orElse: () => '',
          );

          if (colFecha.isNotEmpty && fila[colFecha] != null) {
            try {
              DateTime? fechaFila;
              String valStr = fila[colFecha].toString();
              if (valStr.contains('T')) {
                fechaFila = DateTime.parse(valStr);
              } else if (valStr.contains('-')) {
                fechaFila = DateFormat('yyyy-MM-dd').parse(valStr.split(' ')[0]);
              }

              if (fechaFila != null) {
                if (_fechaInicio != null && fechaFila.isBefore(DateTime(_fechaInicio!.year, _fechaInicio!.month, _fechaInicio!.day))) {
                  continue;
                }
                if (_fechaFin != null && fechaFila.isAfter(DateTime(_fechaFin!.year, _fechaFin!.month, _fechaFin!.day, 23, 59, 59))) {
                  continue;
                }
              }
            } catch (_) {}
          }

          // Extraer productos si es una tabla relacional directa
          String? colNombre = columnas.firstWhere(
            (c) => ['nombre_producto', 'producto', 'nombre', 'descripcion', 'item'].contains(c.toLowerCase()),
            orElse: () => '',
          );
          String? colCant = columnas.firstWhere(
            (c) => ['cantidad', 'cant', 'qty', 'unidades'].contains(c.toLowerCase()),
            orElse: () => '',
          );
          String? colMonto = columnas.firstWhere(
            (c) => ['subtotal', 'total', 'monto', 'precio', 'precio_total'].contains(c.toLowerCase()),
            orElse: () => '',
          );

          if (tabla != 'pedidos' && colNombre.isNotEmpty && colCant.isNotEmpty) {
            String nombre = fila[colNombre]?.toString() ?? 'Producto';
            int cant = int.tryParse(fila[colCant]?.toString() ?? '0') ?? 0;
            double monto = double.tryParse(fila[colMonto]?.toString() ?? '0') ?? 0.0;
            if (cant > 0) {
              _agregarAlResumen(resumenMap, nombre, cant, monto);
            }
          } else {
            // Extraer productos si están guardados como JSON dentro de la tabla pedidos
            for (String col in columnas) {
              dynamic val = fila[col];
              if (val is String && (val.trim().startsWith('[') || val.trim().startsWith('{'))) {
                try {
                  var jsonVal = jsonDecode(val);
                  List<dynamic> items = jsonVal is List ? jsonVal : [jsonVal];
                  for (var item in items) {
                    if (item is Map) {
                      String pNombre = (item['nombre_producto'] ?? item['nombre'] ?? item['producto'] ?? item['descripcion'] ?? 'Producto').toString();
                      int pCant = int.tryParse(item['cantidad']?.toString() ?? item['cant']?.toString() ?? '1') ?? 1;
                      double pPrecio = double.tryParse(item['precio']?.toString() ?? item['precio_unitario']?.toString() ?? '0') ?? 0.0;
                      double pMonto = double.tryParse(item['subtotal']?.toString() ?? item['monto']?.toString() ?? '0') ?? (pCant * pPrecio);

                      _agregarAlResumen(resumenMap, pNombre, pCant, pMonto);
                    }
                  }
                } catch (_) {}
              }
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
        if (resultado.isEmpty) {
          _mensajeDiagnostico = "No se encontraron productos acumulados.\n\nEstructura de BD detectada:\n" + infoEstrucutra.join("\n");
        }
      });
    } catch (e) {
      setState(() {
        _cargando = false;
        _mensajeDiagnostico = "Error al leer base de datos:\n$e";
      });
    }
  }

  void _agregarAlResumen(Map<String, Map<String, dynamic>> map, String nombre, int cant, double monto) {
    if (!map.containsKey(nombre)) {
      map[nombre] = {
        'nombre_producto': nombre,
        'total_cantidad': 0,
        'total_monto': 0.0,
      };
    }
    map[nombre]!['total_cantidad'] = (map[nombre]!['total_cantidad'] as int) + cant;
    map[nombre]!['total_monto'] = (map[nombre]!['total_monto'] as double) + monto;
  }

  Future<void> _seleccionarFechaInicio(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicio ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _fechaInicio = picked);
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
    if (picked != null) {
      setState(() => _fechaFin = picked);
      _cargarResumenProductos();
    }
  }

  void _establecerSemanaActual() {
    final ahora = DateTime.now();
    final inicioSemana = ahora.subtract(Duration(days: ahora.weekday - 1));
    setState(() {
      _fechaInicio = DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);
      _fechaFin = ahora;
    });
    _cargarResumenProductos();
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
          // Filtros de fecha y acceso rápido
          Card(
            margin: const EdgeInsets.all(8),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _seleccionarFechaInicio(context),
                          icon: const Icon(Icons.calendar_today, size: 14),
                          label: Text(
                            _fechaInicio != null ? 'Desde: ${formatoFecha.format(_fechaInicio!)}' : 'Fecha Inicio',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _seleccionarFechaFin(context),
                          icon: const Icon(Icons.calendar_today, size: 14),
                          label: Text(
                            _fechaFin != null ? 'Hasta: ${formatoFecha.format(_fechaFin!)}' : 'Fecha Fin',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _establecerSemanaActual,
                      icon: const Icon(Icons.date_range, size: 14),
                      label: const Text('Esta Semana', style: TextStyle(fontSize: 11)),
                    ),
                  )
                ],
              ),
            ),
          ),

          // Tarjeta de Totales
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Total Unidades', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('$_totalUnidades', style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Monto Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text(formatoMoneda.format(_totalGeneral), style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          // Contenido principal / Lista de productos o diagnósticos
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _productosConsolidados.isNotEmpty
                    ? ListView.builder(
                        itemCount: _productosConsolidados.length,
                        itemBuilder: (context, index) {
                          final item = _productosConsolidados[index];
                          final nombre = item['nombre_producto'] ?? 'Producto';
                          final cant = item['total_cantidad'] ?? 0;
                          final monto = item['total_monto'] ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).primaryColor,
                                child: Text('$cant', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                              title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text('Total unidades vendidas: $cant'),
                              trailing: Text(
                                formatoMoneda.format(monto),
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          );
                        },
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _mensajeDiagnostico,
                          style: const TextStyle(color: Colors.black87, fontSize: 13, fontFamily: 'monospace'),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
