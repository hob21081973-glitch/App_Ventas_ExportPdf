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

  // Lista de semanas detectadas en el historial
  List<String> _semanasDisponibles = ['Todas las semanas'];
  String _semanaSeleccionada = 'Todas las semanas';

  @override
  void initState() {
    super.initState();
    _cargarResumenYSemanas();
  }

  Future<Database> _obtenerBaseDatos() async {
    final path = await getDatabasesPath();
    final dbPath = '$path/app_ventas.db';
    return openDatabase(dbPath);
  }

  Future<void> _cargarResumenYSemanas() async {
    setState(() => _cargando = true);

    try {
      final db = await _obtenerBaseDatos();

      // 1. Obtener lista de tablas
      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'"
      );
      List<String> tablas = tablesResult.map((t) => t['name'].toString()).toList();

      Set<String> semanasDetectadas = {};
      Map<String, Map<String, dynamic>> resumenMap = {};

      for (String tabla in tablas) {
        final pragma = await db.rawQuery("PRAGMA table_info($tabla)");
        List<String> columnas = pragma.map((c) => c['name'].toString()).toList();

        final List<Map<String, dynamic>> filas = await db.query(tabla);

        for (var fila in filas) {
          // Detectar la semana guardada en el pedido
          String semanaFila = '';

          // Buscar columna que contenga el nombre de la semana
          for (String col in columnas) {
            String colLower = col.toLowerCase();
            if (colLower.contains('semana') || colLower.contains('grupo')) {
              if (fila[col] != null && fila[col].toString().trim().isNotEmpty) {
                semanaFila = fila[col].toString().trim();
                semanasDetectadas.add(semanaFila);
                break;
              }
            }
          }

          // Si no está en columnas directas, buscar dentro de datos estructurados/JSON
          if (semanaFila.isEmpty) {
            for (String col in columnas) {
              dynamic val = fila[col];
              if (val is String && val.contains('semana')) {
                try {
                  var jsonVal = jsonDecode(val);
                  if (jsonVal is Map && jsonVal.containsKey('semana')) {
                    semanaFila = jsonVal['semana'].toString().trim();
                    if (semanaFila.isNotEmpty) semanasDetectadas.add(semanaFila);
                  }
                } catch (_) {}
              }
            }
          }

          // Aplicar filtro de la semana seleccionada
          if (_semanaSeleccionada != 'Todas las semanas' && semanaFila.isNotEmpty) {
            if (semanaFila.toLowerCase() != _semanaSeleccionada.toLowerCase()) {
              continue; // Salta los pedidos que no pertenezcan a la semana seleccionada
            }
          }

          // Extraer productos del pedido
          _procesarProductosDeFila(fila, columnas, resumenMap, tabla);
        }
      }

      // Actualizar la lista desplegable de semanas
      List<String> listaSemanas = ['Todas las semanas', ...semanasDetectadas.toList()..sort()];

      List<Map<String, dynamic>> resultado = resumenMap.values.toList();
      resultado.sort((a, b) => (b['total_cantidad'] as int).compareTo(a['total_cantidad'] as int));

      double sumaMonto = 0.0;
      int sumaCantidad = 0;
      for (var item in resultado) {
        sumaCantidad += (item['total_cantidad'] as int);
        sumaMonto += (item['total_monto'] as double);
      }

      setState(() {
        _semanasDisponibles = listaSemanas;
        if (!_semanasDisponibles.contains(_semanaSeleccionada)) {
          _semanaSeleccionada = 'Todas las semanas';
        }
        _productosConsolidados = resultado;
        _totalUnidades = sumaCantidad;
        _totalGeneral = sumaMonto;
        _cargando = false;
      });
    } catch (e) {
      debugPrint("Error al cargar resumen por semana: $e");
      setState(() => _cargando = false);
    }
  }

  void _procesarProductosDeFila(
    Map<String, dynamic> fila,
    List<String> columnas,
    Map<String, Map<String, dynamic>> resumenMap,
    String tabla,
  ) {
    // Caso 1: Tabla relacional directa de detalle de productos
    String? colNombre = columnas.firstWhere(
      (c) => ['nombre_producto', 'producto', 'nombre', 'descripcion'].contains(c.toLowerCase()),
      orElse: () => '',
    );
    String? colCant = columnas.firstWhere(
      (c) => ['cantidad', 'cant', 'qty', 'unidades'].contains(c.toLowerCase()),
      orElse: () => '',
    );
    String? colMonto = columnas.firstWhere(
      (c) => ['subtotal', 'total', 'monto', 'precio'].contains(c.toLowerCase()),
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
      // Caso 2: Productos guardados como lista/JSON en la tabla de pedidos
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

  Future<void> _generarPdfResumen() async {
    final pdf = pw.Document();
    final formatoMoneda = NumberFormat.currency(symbol: 'L ', decimalDigits: 2);
    final fechaHoy = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

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
            pw.Text('Filtro: $_semanaSeleccionada', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
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
      name: 'Resumen_Productos_${_semanaSeleccionada.replaceAll(' ', '_')}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatoMoneda = NumberFormat.currency(symbol: 'L ', decimalDigits: 2);

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
            onPressed: _cargarResumenYSemanas,
          ),
        ],
      ),
      body: Column(
        children: [
          // Selector desplegable de Semanas
          Card(
            margin: const EdgeInsets.all(10),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.view_week, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Text('Semana:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _semanaSeleccionada,
                        isExpanded: true,
                        items: _semanasDisponibles.map((String semana) {
                          return DropdownMenuItem<String>(
                            value: semana,
                            child: Text(
                              semana,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (nuevoValor) {
                          if (nuevoValor != null) {
                            setState(() {
                              _semanaSeleccionada = nuevoValor;
                            });
                            _cargarResumenYSemanas();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Resumen de Totales
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

          // Lista de Productos Consolidados
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _productosConsolidados.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text(
                            'No hay productos registrados en el historial para la semana seleccionada.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 14),
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
                                child: Text('$cant', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                              title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text('Unidades en $_semanaSeleccionada: $cant'),
                              trailing: Text(
                                formatoMoneda.format(monto),
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
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
