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

  @override
  void initState() {
    super.initState();
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
      final List<Map<String, dynamic>> resultado = await db.rawQuery('''
        SELECT 
          nombre_producto,
          SUM(cantidad) as total_cantidad,
          AVG(precio_unitario) as precio_promedio,
          SUM(subtotal) as total_monto
        FROM detalle_pedidos
        GROUP BY nombre_producto
        ORDER BY total_cantidad DESC
      ''');

      double sumaMonto = 0.0;
      int sumaCantidad = 0;

      for (var item in resultado) {
        sumaCantidad += (item['total_cantidad'] as num? ?? 0).toInt();
        sumaMonto += (item['total_monto'] as num? ?? 0).toDouble();
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
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _productosConsolidados.isEmpty
              ? const Center(child: Text('No hay productos registrados.'))
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('Total Unidades', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('$_totalUnidades', style: const TextStyle(fontSize: 18, color: Colors.blue)),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('Monto Total', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(formatoMoneda.format(_totalGeneral), style: const TextStyle(fontSize: 18, color: Colors.green)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _productosConsolidados.length,
                        itemBuilder: (context, index) {
                          final item = _productosConsolidados[index];
                          final nombre = item['nombre_producto'] ?? 'Producto';
                          final cant = item['total_cantidad'] ?? 0;
                          final monto = item['total_monto'] ?? 0.0;

                          return ListTile(
                            leading: CircleAvatar(child: Text('$cant')),
                            title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: Text(formatoMoneda.format(monto), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
