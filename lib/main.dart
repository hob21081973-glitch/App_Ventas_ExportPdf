import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Notificador global para actualizar datos en tiempo real entre pestañas
final ValueNotifier<int> changeNotifierPedidos = ValueNotifier<int>(0); 

// URLs de Google Sheets (Reemplaza con tus enlaces CSV publicados)
const String urlClientesCSV = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vTmtKhEE5ziDtm_BQdAeOy8c-Z6H6_GbyKcPOvtdjfKtXgxYObBUB-PlK0ldsiwrW78aabDzei-R2Cd/pub?gid=0&single=true&output=csv';
const String urlProductosCSV = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vTmtKhEE5ziDtm_BQdAeOy8c-Z6H6_GbyKcPOvtdjfKtXgxYObBUB-PlK0ldsiwrW78aabDzei-R2Cd/pub?gid=1903712481&single=true&output=csv';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppVentasExportPdf());
}

class AppVentasExportPdf extends StatelessWidget {
  const AppVentasExportPdf({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Ventas ExportPdf',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const MenuPrincipal(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==========================================
// BASE DE DATOS LOCAL (SQLITE)
// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ventas_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/$filePath';
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clientes (
        codigo TEXT PRIMARY KEY,
        nombre TEXT,
        telefono TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE productos (
        codigo TEXT PRIMARY KEY,
        nombre TEXT,
        precio REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE pedidos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero_pedido TEXT,
        cliente TEXT,
        productos_json TEXT,
        total REAL,
        fecha TEXT
      )
    ''');
  }

  Future<void> sincronizarClientesDesdeCSV(String csvData) async {
    final db = await instance.database;
    List<String> lineas = csvData.split('\n');
    await db.transaction((txn) async {
      await txn.delete('clientes');
      for (int i = 1; i < lineas.length; i++) {
        var linea = lineas[i].trim();
        if (linea.isEmpty) continue;
        List<String> cols = linea.split(',');
        if (cols.length >= 3) {
          await txn.insert('clientes', {
            'codigo': cols[0].replaceAll('"', '').trim(),
            'nombre': cols[1].replaceAll('"', '').trim(),
            'telefono': cols[2].replaceAll('"', '').trim(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<void> sincronizarProductosDesdeCSV(String csvData) async {
    final db = await instance.database;
    List<String> lineas = csvData.split('\n');
    await db.transaction((txn) async {
      await txn.delete('productos');
      for (int i = 1; i < lineas.length; i++) {
        var linea = lineas[i].trim();
        if (linea.isEmpty) continue;
        List<String> cols = linea.split(',');
        if (cols.length >= 3) {
          String precioStr = cols[2].replaceAll('L', '').replaceAll(',', '').replaceAll('"', '').trim();
          double precio = double.tryParse(precioStr) ?? 0.0;
          await txn.insert('productos', {
            'codigo': cols[0].replaceAll('"', '').trim(),
            'nombre': cols[1].replaceAll('"', '').trim(),
            'precio': precio,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }
}

// ==========================================
// MENÚ PRINCIPAL CON PESTAÑAS
// ==========================================
class MenuPrincipal extends StatefulWidget {
  const MenuPrincipal({super.key});

  @override
  State<MenuPrincipal> createState() => MenuPrincipalState();
}

class MenuPrincipalState extends State<MenuPrincipal> {
  int _indiceActual = 0;
  
  int? editandoPedidoId;
  String? editandoNumeroPedidoFijo;
  String? clienteEnCurso;
  List<Map<String, dynamic>> productosEnCurso = [];

  @override
  void initState() {
    super.initState();
    _cargarBorradorLocal();
  }

  Future<void> _guardarBorradorLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('editandoPedidoId', editandoPedidoId ?? -1);
    await prefs.setString('editandoNumeroPedidoFijo', editandoNumeroPedidoFijo ?? '');
    await prefs.setString('clienteEnCurso', clienteEnCurso ?? '');
    await prefs.setString('productosEnCurso', jsonEncode(productosEnCurso));
  }

  Future<void> _cargarBorradorLocal() async {
    final prefs = await SharedPreferences.getInstance();
    int? idTemp = prefs.getInt('editandoPedidoId');
    if (idTemp != null && idTemp != -1) {
      editandoPedidoId = idTemp;
    }
    String? numTemp = prefs.getString('editandoNumeroPedidoFijo');
    if (numTemp != null && numTemp.isNotEmpty) {
      editandoNumeroPedidoFijo = numTemp;
    }
    String? cliTemp = prefs.getString('clienteEnCurso');
    if (cliTemp != null && cliTemp.isNotEmpty) {
      clienteEnCurso = cliTemp;
    }
    String? prodTemp = prefs.getString('productosEnCurso');
    if (prodTemp != null && prodTemp.isNotEmpty) {
      try {
        List<dynamic> dec = jsonDecode(prodTemp);
        productosEnCurso = dec.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
    setState(() {});
  }

  void cargarPedidoParaEditar(int id, String numeroPedido, String cliente, List<Map<String, dynamic>> productos) {
    setState(() {
      editandoPedidoId = id;
      editandoNumeroPedidoFijo = numeroPedido;
      clienteEnCurso = cliente;
      productosEnCurso = List.from(productos);
      _indiceActual = 0; // Cambiar a la pestaña "Crear"
    });
    _guardarBorradorLocal();
  }

  void limpiarPedidoEnCurso() async {
    setState(() {
      editandoPedidoId = null;
      editandoNumeroPedidoFijo = null;
      clienteEnCurso = null;
      productosEnCurso.clear();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pantallas = [
      VistaCrearPedido(
        onPedidoGuardado: limpiarPedidoEnCurso,
        onCambioDato: _guardarBorradorLocal,
      ),
      const VistaHistorialPedidos(),
      const VistaGestionClientes(),
      const VistaGestionProductos(),
      const VistaResumenGeneral(),
      const VistaResumenProductos(),
      const VistaExportarPdf(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _indiceActual,
        children: pantallas,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indiceActual,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _indiceActual = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.add_shopping_cart), label: 'Crear'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historial'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Clientes'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Productos'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Resumen'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Por Prod.'),
          BottomNavigationBarItem(icon: Icon(Icons.picture_as_pdf), label: 'Exportar'),
        ],
      ),
    );
  }
}

// ==========================================
// 1. PESTAÑA: CREAR PEDIDO
// ==========================================
class VistaCrearPedido extends StatefulWidget {
  final VoidCallback onPedidoGuardado;
  final VoidCallback onCambioDato;
  const VistaCrearPedido({super.key, required this.onPedidoGuardado, required this.onCambioDato});

  @override
  State<VistaCrearPedido> createState() => _VistaCrearPedidoState();
}

class _VistaCrearPedidoState extends State<VistaCrearPedido> {
  Future<int> _obtenerSiguienteNumeroPedido() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db.rawQuery('SELECT COUNT(*) as total FROM pedidos');
    int count = Sqflite.firstIntValue(resultado) ?? 0;
    return (count % 99) + 1;
  }

  void _guardarPedido() async {
    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    if (mainState?.clienteEnCurso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar un cliente obligatoriamente')),
      );
      return;
    }
    if (mainState == null || mainState.productosEnCurso.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregue al menos un producto al pedido')),
      );
      return;
    }

    String numPedidoStr;
    if (mainState.editandoNumeroPedidoFijo != null) {
      numPedidoStr = mainState.editandoNumeroPedidoFijo!;
    } else {
      int numSeq = await _obtenerSiguienteNumeroPedido();
      numPedidoStr = 'Pedido #${numSeq.toString().padLeft(2, '0')}';
    }

    double total = mainState.productosEnCurso.fold<double>(
      0.0, 
      (sum, item) => sum + ((item['precio'] as num).toDouble() * (item['cantidad'] as num).toDouble())
    );

    String fecha = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    
    String productosStr = mainState.productosEnCurso.map((p) {
      String com = (p['comentario'] != null && p['comentario'].toString().trim().isNotEmpty)
          ? ' [${p['comentario']}]'
          : '';
      return "${p['nombre']}$com (x${p['cantidad']})";
    }).join('; ');

    final db = await DatabaseHelper.instance.database;
    
    if (mainState.editandoPedidoId != null) {
      await db.update('pedidos', {
        'numero_pedido': numPedidoStr,
        'cliente': mainState.clienteEnCurso,
        'productos_json': productosStr,
        'total': total,
      }, where: 'id = ?', whereArgs: [mainState.editandoPedidoId]);
    } else {
      await db.insert('pedidos', {
        'numero_pedido': numPedidoStr,
        'cliente': mainState.clienteEnCurso,
        'productos_json': productosStr,
        'total': total,
        'fecha': fecha,
      });
    }

    widget.onPedidoGuardado();
    changeNotifierPedidos.value++;
    setState(() {});

    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('¡$numPedidoStr Guardado con éxito!')),
    );
  }

  void _abrirBuscadorClientes() {
    showDialog(
      context: context,
      builder: (context) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Buscar Cliente'),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Nombre o código del cliente...',
                          suffixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          setStateDialog(() {
                            filtro = val.trim();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: DatabaseHelper.instance.database.then((db) {
                            return db.query('clientes', where: 'nombre LIKE ? OR codigo LIKE ?', whereArgs: ['%$filtro%', '%$filtro%']);
                          }),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                            final clientes = snapshot.data!;
                            if (clientes.isEmpty) {
                              return const Center(child: Text('No se encontraron clientes', style: TextStyle(color: Colors.grey)));
                            }
                            return ListView.builder(
                              itemCount: clientes.length,
                              itemBuilder: (context, index) {
                                final c = clientes[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    title: Text('Cod: ${c['codigo']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                                    subtitle: Text('${c['nombre']}\nTel: ${c['telefono']}', style: const TextStyle(fontSize: 14)),
                                    isThreeLine: true,
                                    onTap: () {
                                      final mainState = this.context.findAncestorStateOfType<MenuPrincipalState>();
                                      if (mainState != null) {
                                        mainState.setState(() {
                                          mainState.clienteEnCurso = c['nombre'];
                                        });
                                        widget.onCambioDato();
                                      }
                                      Navigator.pop(context);
                                      setState(() {});
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _abrirBuscadorProductos() {
    showDialog(
      context: context,
      builder: (context) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Buscar Producto'),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Nombre o código del producto...',
                          suffixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          setStateDialog(() {
                            filtro = val.trim();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: DatabaseHelper.instance.database.then((db) {
                            return db.query('productos', where: 'nombre LIKE ? OR codigo LIKE ?', whereArgs: ['%$filtro%', '%$filtro%']);
                          }),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                            final productos = snapshot.data!;
                            if (productos.isEmpty) {
                              return const Center(child: Text('No se encontraron productos', style: TextStyle(color: Colors.grey)));
                            }
                            return ListView.builder(
                              itemCount: productos.length,
                              itemBuilder: (context, index) {
                                final p = productos[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    title: Text('Cod: ${p['codigo']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                                    subtitle: Text('${p['nombre']}\nPrecio: L ${p['precio'].toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
                                    isThreeLine: true,
                                    onTap: () {
                                      final mainState = this.context.findAncestorStateOfType<MenuPrincipalState>();
                                      if (mainState != null) {
                                        mainState.setState(() {
                                          var existenteIndex = mainState.productosEnCurso.indexWhere(
                                            (item) => item['nombre'] == p['nombre'],
                                          );
                                          if (existenteIndex != -1) {
                                            mainState.productosEnCurso[existenteIndex]['cantidad']++;
                                          } else {
                                            mainState.productosEnCurso.add({
                                              'nombre': p['nombre'],
                                              'precio': p['precio'],
                                              'cantidad': 1,
                                              'comentario': '',
                                            });
                                          }
                                        });
                                        widget.onCambioDato();
                                      }
                                      Navigator.pop(context);
                                      setState(() {});
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _pedirComentario(int index) {
    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    if (mainState == null) return;
    TextEditingController comCtrl = TextEditingController(text: mainState.productosEnCurso[index]['comentario'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comentario / Detalle'),
        content: TextField(
          controller: comCtrl,
          decoration: const InputDecoration(labelText: 'Ej. Color rojo, Talla L, Fragancia vainilla...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                mainState.productosEnCurso[index]['comentario'] = comCtrl.text.trim();
              });
              widget.onCambioDato();
              Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoGestionProducto(int index) {
    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    if (mainState == null) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (index >= mainState.productosEnCurso.length) {
            return const SizedBox.shrink();
          }
          var item = mainState.productosEnCurso[index];
          return AlertDialog(
            title: Text(item['nombre'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cantidad actual: ${item['cantidad']}', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () {
                        mainState.setState(() {
                          if (item['cantidad'] > 1) {
                            item['cantidad']--;
                          } else {
                            mainState.productosEnCurso.removeAt(index);
                          }
                        });
                        widget.onCambioDato();
                        setStateDialog(() {});
                        setState(() {});
                        if (index >= mainState.productosEnCurso.length || mainState.productosEnCurso.isEmpty) {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.remove, size: 16),
                      label: const Text('Menos'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      onPressed: () {
                        mainState.setState(() {
                          item['cantidad']++;
                        });
                        widget.onCambioDato();
                        setStateDialog(() {});
                        setState(() {});
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Más'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () {
                    mainState.setState(() {
                      mainState.productosEnCurso.removeAt(index);
                    });
                    widget.onCambioDato();
                    Navigator.pop(context);
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete),
                  label: const Text('Eliminar del pedido'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    bool estaEditando = mainState?.editandoPedidoId != null;
    double totalActual = mainState?.productosEnCurso.fold<double>(
      0.0, 
      (sum, item) => sum + ((item['precio'] as num).toDouble() * (item['cantidad'] as num).toDouble())
    ) ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(estaEditando ? 'Editando ${mainState?.editandoNumeroPedidoFijo}' : 'Crear Pedido'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (estaEditando)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.amberAccent),
              tooltip: 'Cancelar Edición',
              onPressed: () => setState(() => mainState?.limpiarPedidoEnCurso()),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _abrirBuscadorClientes,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          mainState?.clienteEnCurso ?? 'Toca la lupa para seleccionar cliente...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: mainState?.clienteEnCurso != null ? FontWeight.bold : FontWeight.normal,
                            color: mainState?.clienteEnCurso != null ? Colors.black87 : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  icon: const Icon(Icons.search),
                  tooltip: 'Buscar Cliente',
                  onPressed: _abrirBuscadorClientes,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text('Agregar Productos al Pedido:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                IconButton(
                  style: IconButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  icon: const Icon(Icons.search),
                  tooltip: 'Buscar Producto',
                  onPressed: _abrirBuscadorProductos,
                ),
              ],
            ),
            const Divider(height: 15),
            Expanded(
              child: (mainState?.productosEnCurso.isEmpty ?? true)
                  ? const Center(
                      child: Text('No hay productos agregados todavía.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    )
                  : ListView.builder(
                      itemCount: mainState?.productosEnCurso.length ?? 0,
                      itemBuilder: (context, idx) {
                        var item = mainState!.productosEnCurso[idx];
                        String comText = (item['comentario'] != null && item['comentario'].toString().isNotEmpty)
                            ? item['comentario']
                            : '';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _pedirComentario(idx),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['nombre'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                        const SizedBox(height: 2),
                                        Text('Cant: ${item['cantidad']} x L ${item['precio']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
                                        if (comText.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text('Detalle: $comText', style: const TextStyle(fontSize: 10, color: Colors.indigo, fontStyle: FontStyle.italic)),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _mostrarDialogoGestionProducto(idx),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Text(
                                      'L ${(item['precio'] * item['cantidad']).toStringAsFixed(2)}', 
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total: L ${totalActual.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: _guardarPedido,
                  icon: const Icon(Icons.save),
                  label: Text(estaEditando ? 'Actualizar Pedido' : 'Guardar Pedido'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. PESTAÑA: HISTORIAL DE PEDIDOS
// ==========================================
class VistaHistorialPedidos extends StatefulWidget {
  const VistaHistorialPedidos({super.key});

  @override
  State<VistaHistorialPedidos> createState() => _VistaHistorialPedidosState();
}

class _VistaHistorialPedidosState extends State<VistaHistorialPedidos> {
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    changeNotifierPedidos.addListener(_recargar);
  }

  @override
  void dispose() {
    changeNotifierPedidos.removeListener(_recargar);
    super.dispose();
  }

  void _recargar() {
    if (mounted) setState(() {});
  }

  Future<List<Map<String, dynamic>>> _obtenerPedidos() async {
    final db = await DatabaseHelper.instance.database;
    if (_filtro.isEmpty) {
      return await db.query('pedidos', orderBy: 'id DESC');
    } else {
      return await db.query(
        'pedidos',
        where: 'cliente LIKE ? OR numero_pedido LIKE ?',
        whereArgs: ['%$_filtro%', '%$_filtro%'],
        orderBy: 'id DESC',
      );
    }
  }

  void _eliminarPedido(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('pedidos', where: 'id = ?', whereArgs: [id]);
    changeNotifierPedidos.value++;
    setState(() {});
  }

  void _editarPedido(Map<String, dynamic> pedido) async {
    final mainState = context.findAncestorStateOfType<MenuPrincipalState>();
    if (mainState == null) return;
    
    List<Map<String, dynamic>> productosEdit = [];
    String prodStr = pedido['productos_json']?.toString() ?? '';
    double totalPedido = (pedido['total'] as num?)?.toDouble() ?? 0.0;
    
    List<String> items = prodStr.split(';');
    int cantidadTotalItems = 0;
    
    List<Map<String, dynamic>> itemsTemporales = [];
    for (var item in items) {
      item = item.trim();
      if (item.isEmpty) continue;
      
      RegExp regExp = RegExp(r'\s*\(x(\d+)\)$');
      Match? match = regExp.firstMatch(item);
      int cantidad = 1;
      String nombreProd = item;
      
      if (match != null) {
        cantidad = int.tryParse(match.group(1) ?? '1') ?? 1;
        nombreProd = item.replaceFirst(regExp, '').trim();
      }
      
      String comentario = '';
      int bracketStart = nombreProd.indexOf('[');
      int bracketEnd = nombreProd.lastIndexOf(']');
      if (bracketStart != -1 && bracketEnd != -1 && bracketEnd > bracketStart) {
        comentario = nombreProd.substring(bracketStart + 1, bracketEnd).trim();
        nombreProd = nombreProd.substring(0, bracketStart).trim();
      }
      
      cantidadTotalItems += cantidad;
      itemsTemporales.add({
        'nombre': nombreProd,
        'cantidad': cantidad,
        'comentario': comentario,
      });
    }

    final db = await DatabaseHelper.instance.database;
    
    for (var temp in itemsTemporales) {
      double precioUnitario = 0.0;
      final resProd = await db.query(
        'productos',
        where: 'nombre = ?',
        whereArgs: [temp['nombre']],
        limit: 1,
      );
      
      if (resProd.isNotEmpty) {
        precioUnitario = (resProd.first['precio'] as num?)?.toDouble() ?? 0.0;
      } else if (cantidadTotalItems > 0) {
        precioUnitario = totalPedido / cantidadTotalItems;
      }

      productosEdit.add({
        'nombre': temp['nombre'],
        'precio': precioUnitario,
        'cantidad': temp['cantidad'],
        'comentario': temp['comentario'],
      });
    }

    mainState.cargarPedidoParaEditar(
      pedido['id'],
      pedido['numero_pedido'],
      pedido['cliente'],
      productosEdit,
    );
  }

  // ==========================================
  // FUNCIÓN PARA GENERAR EL PDF CON EL NUEVO DISEÑO (ESTILO DISCOSMO)
  // ==========================================
  Future<void> _exportarPdfPedidoIndividual(Map<String, dynamic> pedido) async {
    final pdf = pw.Document();

    // Obtener detalles del cliente desde la base de datos (teléfono, etc.)
    final db = await DatabaseHelper.instance.database;
    final clienteNombre = pedido['cliente']?.toString() ?? 'Cliente';
    final resCliente = await db.query(
      'clientes',
      where: 'nombre = ?',
      whereArgs: [clienteNombre],
      limit: 1,
    );

    String telefonoCliente = '';
    String codigoCliente = '';
    if (resCliente.isNotEmpty) {
      telefonoCliente = resCliente.first['telefono']?.toString() ?? '';
      codigoCliente = resCliente.first['codigo']?.toString() ?? '';
    }

    // Procesar los productos del JSON
    String prodStr = pedido['productos_json']?.toString() ?? '';
    List<String> items = prodStr.split(';');
    List<List<String>> filasProductos = [];
    int conteoTotalUnidades = 0;

    for (var item in items) {
      item = item.trim();
      if (item.isEmpty) continue;

      RegExp regExp = RegExp(r'\s*\(x(\d+)\)$');
      Match? match = regExp.firstMatch(item);
      int cantidad = 1;
      String nombreProd = item;

      if (match != null) {
        cantidad = int.tryParse(match.group(1) ?? '1') ?? 1;
        nombreProd = item.replaceFirst(regExp, '').trim();
      }

      conteoTotalUnidades += cantidad;

      // Buscar el precio unitario del producto en la BD local
      double precioUnitario = 0.0;
      final resProd = await db.query(
        'productos',
        where: 'nombre = ?',
        whereArgs: [nombreProd],
        limit: 1,
      );

      if (resProd.isNotEmpty) {
        precioUnitario = (resProd.first['precio'] as num?)?.toDouble() ?? 0.0;
      }

      double valorTotalFila = precioUnitario * cantidad;

      filasProductos.add([
        cantidad.toString(),
        nombreProd,
        precioUnitario.toStringAsFixed(2),
        valorTotalFila.toStringAsFixed(2),
      ]);
    }

    double totalPedido = (pedido['total'] as num?)?.toDouble() ?? 0.0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Encabezado de la Empresa y Datos del Pedido
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'DISCOSMO',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo900,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text('Fotografía de marco adicional', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('FECHA: ${pedido['fecha']?.toString().substring(0, 10) ?? ''}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.SizedBox(height: 3),
                      pw.Text('PEDIDO #: ${pedido['numero_pedido']?.toString() ?? ''}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.indigo900)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 10),

              // Datos del Cliente
              pw.Text('CLIENTE:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              pw.SizedBox(height: 2),
              pw.Text(clienteNombre, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              if (codigoCliente.isNotEmpty)
                pw.Text('Código: $codigoCliente', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              if (telefonoCliente.isNotEmpty)
                pw.Text('Teléfono: $telefonoCliente', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              
              pw.SizedBox(height: 20),

              // Tabla de Productos
              pw.Table.fromTextArray(
                headers: ['Cant.', 'Descripción', 'PRECIO UNITARIO', 'VALOR TOTAL'],
                data: filasProductos,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
                cellStyle: const pw.TextStyle(fontSize: 10),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(5),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                },
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  0: pw.Alignment.center,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
              ),

              pw.SizedBox(height: 20),

              // Sección Inferior: Conteo de productos y Totales
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // CONTEO DE PRODUCTOS
                  pw.Container(
                    padding: const EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    width: 180,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('CONTEO DE PRODUCTOS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.indigo900)),
                        pw.SizedBox(height: 5),
                        pw.Text('Total de ítems: $conteoTotalUnidades', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),

                  // SUBtotales y Totales
                  pw.SizedBox(
                    width: 220,
                    child: pw.Column(
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Subtotal', style: const pw.TextStyle(fontSize: 10)),
                            pw.Text('L ${totalPedido.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                          ],
                        ),
                        pw.SizedBox(height: 5),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Impuesto sobre las ventas', style: const pw.TextStyle(fontSize: 10)),
                            pw.Text('L 0.00', style: const pw.TextStyle(fontSize: 10)),
                          ],
                        ),
                        pw.Divider(color: PdfColors.grey400),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('GRAN Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                            pw.Text('L ${totalPedido.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.indigo900)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    // Guardar y abrir vista previa de impresión/descarga
    try {
      Directory? directorio;
      if (Platform.isAndroid) {
        directorio = Directory('/storage/emulated/0/Download');
        if (!await directorio.exists()) {
          directorio = await getExternalStorageDirectory();
        }
      } else {
        directorio = await getApplicationDocumentsDirectory();
      }
      
      String numPedLimpio = (pedido['numero_pedido']?.toString() ?? 'pedido').replaceAll('#', '').replaceAll(' ', '_');
      final ruta = '${directorio!.path}/Nota_$numPedLimpio.pdf';
      final archivo = File(ruta);
      await archivo.writeAsBytes(await pdf.save());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF guardado en Descargas: Nota_$numPedLimpio.pdf')),
      );

      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar el PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Pedidos'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por cliente o número de pedido...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() {
                  _filtro = val.trim();
                });
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _obtenerPedidos(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final pedidos = snapshot.data!;
                  if (pedidos.isEmpty) {
                    return const Center(child: Text('No hay pedidos registrados', style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    itemCount: pedidos.length,
                    itemBuilder: (context, index) {
                      final p = pedidos[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text('${p['numero_pedido']} - ${p['cliente']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                          subtitle: Text('Productos: ${p['productos_json']}\nFecha: ${p['fecha']}\nTotal: L ${(p['total'] as num).toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Botón para exportar el PDF individual con el nuevo formato
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.indigo),
                                tooltip: 'Generar PDF del Pedido',
                                onPressed: () => _exportarPdfPedidoIndividual(p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _editarPedido(p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _eliminarPedido(p['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. PESTAÑA: GESTIÓN DE CLIENTES
// ==========================================
class VistaGestionClientes extends StatefulWidget {
  const VistaGestionClientes({super.key});

  @override
  State<VistaGestionClientes> createState() => _VistaGestionClientesState();
}

class _VistaGestionClientesState extends State<VistaGestionClientes> {
  bool _cargando = false;

  Future<void> _sincronizar() async {
    setState(() => _cargando = true);
    try {
      final response = await http.get(Uri.parse(urlClientesCSV));
      if (response.statusCode == 200) {
        await DatabaseHelper.instance.sincronizarClientesDesdeCSV(response.body);
        if(!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clientes sincronizados con éxito')));
      } else {
        throw Exception('Error al descargar CSV');
      }
    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de sincronización: $e')));
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Clientes'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar desde Google Sheets',
            onPressed: _cargando ? null : _sincronizar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.database.then((db) => db.query('clientes')),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final clientes = snapshot.data!;
                if (clientes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('No hay clientes. Sincroniza desde Google Sheets.'),
                        const SizedBox(height: 10),
                        ElevatedButton(onPressed: _sincronizar, child: const Text('Sincronizar Ahora'))
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: clientes.length,
                  itemBuilder: (context, index) {
                    final c = clientes[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        title: Text(c['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Código: ${c['codigo']} | Tel: ${c['telefono']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.phone, color: Colors.green),
                          onPressed: () async {
                            final Uri launchUri = Uri(scheme: 'tel', path: c['telefono']);
                            if (await canLaunchUrl(launchUri)) {
                              await launchUrl(launchUri);
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ==========================================
// 4. PESTAÑA: GESTIÓN DE PRODUCTOS
// ==========================================
class VistaGestionProductos extends StatefulWidget {
  const VistaGestionProductos({super.key});

  @override
  State<VistaGestionProductos> createState() => _VistaGestionProductosState();
}

class _VistaGestionProductosState extends State<VistaGestionProductos> {
  bool _cargando = false;

  Future<void> _sincronizar() async {
    setState(() => _cargando = true);
    try {
      final response = await http.get(Uri.parse(urlProductosCSV));
      if (response.statusCode == 200) {
        await DatabaseHelper.instance.sincronizarProductosDesdeCSV(response.body);
        if(!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Productos sincronizados con éxito')));
      } else {
        throw Exception('Error al descargar CSV');
      }
    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de sincronización: $e')));
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Productos'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar desde Google Sheets',
            onPressed: _cargando ? null : _sincronizar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.database.then((db) => db.query('productos')),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final productos = snapshot.data!;
                if (productos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('No hay productos. Sincroniza desde Google Sheets.'),
                        const SizedBox(height: 10),
                        ElevatedButton(onPressed: _sincronizar, child: const Text('Sincronizar Ahora'))
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: productos.length,
                  itemBuilder: (context, index) {
                    final p = productos[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        title: Text(p['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Código: ${p['codigo']}'),
                        trailing: Text('L ${(p['precio'] as num).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ==========================================
// 5. PESTAÑA: RESUMEN GENERAL
// ==========================================
class VistaResumenGeneral extends StatefulWidget {
  const VistaResumenGeneral({super.key});

  @override
  State<VistaResumenGeneral> createState() => _VistaResumenGeneralState();
}

class _VistaResumenGeneralState extends State<VistaResumenGeneral> {
  @override
  void initState() {
    super.initState();
    changeNotifierPedidos.addListener(_recargar);
  }

  @override
  void dispose() {
    changeNotifierPedidos.removeListener(_recargar);
    super.dispose();
  }

  void _recargar() {
    if (mounted) setState(() {});
  }

  Future<Map<String, dynamic>> _obtenerResumen() async {
    final db = await DatabaseHelper.instance.database;
    final totalPedidosRes = await db.rawQuery('SELECT COUNT(*) as count, SUM(total) as suma FROM pedidos');
    var resultado = totalPedidosRes.first;
    int count = resultado['count'] as int? ?? 0;
    double suma = (resultado['suma'] as num?)?.toDouble() ?? 0.0;
    return {'count': count, 'suma': suma};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen General'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _obtenerResumen(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Text('Total de Pedidos Realizados', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        const SizedBox(height: 10),
                        Text('${data['count']}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Text('Monto Total Vendido', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        const SizedBox(height: 10),
                        Text('L ${(data['suma'] as double).toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// 6. PESTAÑA: RESUMEN POR PRODUCTO
// ==========================================
class VistaResumenProductos extends StatefulWidget {
  const VistaResumenProductos({super.key});

  @override
  State<VistaResumenProductos> createState() => _VistaResumenProductosState();
}

class _VistaResumenProductosState extends State<VistaResumenProductos> {
  Future<Map<String, int>> _obtenerResumenProductos() async {
    final db = await DatabaseHelper.instance.database;
    final pedidos = await db.query('pedidos');
    Map<String, int> conteoProductos = {};
    for (var pedido in pedidos) {
      String productosJson = pedido['productos_json']?.toString() ?? '';
      List<String> items = productosJson.split(';');
      for (var item in items) {
        item = item.trim();
        if (item.isEmpty) continue;
        RegExp regExp = RegExp(r'\s*\(x(\d+)\)$');
        Match? match = regExp.firstMatch(item);
        int cantidad = 1;
        String nombreProd = item;
        if (match != null) {
          cantidad = int.tryParse(match.group(1) ?? '1') ?? 1;
          nombreProd = item.replaceFirst(regExp, '').trim();
          
          int bracketIdx = nombreProd.indexOf(' [');
          if (bracketIdx != -1) {
            nombreProd = nombreProd.substring(0, bracketIdx).trim();
          }
        }
        conteoProductos[nombreProd] = (conteoProductos[nombreProd] ?? 0) + cantidad;
      }
    }
    return conteoProductos;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen por Producto'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, int>>(
        future: _obtenerResumenProductos(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No hay productos vendidos aún.'));
          }
          final resumen = snapshot.data!.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          return ListView.builder(
            itemCount: resumen.length,
            itemBuilder: (context, index) {
              final entry = resumen[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Total: ${entry.value}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ==========================================
// 7. PESTAÑA: EXPORTAR PDF
// ==========================================
class VistaExportarPdf extends StatefulWidget {
  const VistaExportarPdf({super.key});

  @override
  State<VistaExportarPdf> createState() => _VistaExportarPdfState();
}

class _VistaExportarPdfState extends State<VistaExportarPdf> {
  int? _idPedidoInicio;
  int? _idPedidoFin;
  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  Future<void> _guardarYCompartirPdf(pw.Document pdf, String nombreArchivo) async {
    try {
      Directory? directorio;
      if (Platform.isAndroid) {
        directorio = Directory('/storage/emulated/0/Download');
        if (!await directorio.exists()) {
          directorio = await getExternalStorageDirectory();
        }
      } else {
        directorio = await getApplicationDocumentsDirectory();
      }
      final ruta = '${directorio!.path}/$nombreArchivo';
      final archivo = File(ruta);
      await archivo.writeAsBytes(await pdf.save());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('¡Guardado en Descargas: $nombreArchivo')),
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar el archivo: $e')),
      );
    }
  }

  Future<void> _generarPdfGeneral() async {
    final db = await DatabaseHelper.instance.database;
    String query = 'SELECT * FROM pedidos';
    List<String> args = [];
    if (_fechaInicio != null && _fechaFin != null) {
      String inicioStr = DateFormat('yyyy-MM-dd').format(_fechaInicio!);
      String finStr = '${DateFormat('yyyy-MM-dd').format(_fechaFin!)} 23:59';
      query += ' WHERE fecha BETWEEN ? AND ?';
      args = [inicioStr, finStr];
    }
    query += ' ORDER BY id DESC';
    final pedidos = await db.rawQuery(query, args);
    if (pedidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay pedidos en el rango de fechas seleccionado')),
      );
      return;
    }
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        build: (pw.Context context) {
          return [
            pw.Text('Reporte General de Ventas', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            if (_fechaInicio != null && _fechaFin != null)
              pw.Text('Del: ${DateFormat('dd/MM/yyyy').format(_fechaInicio!)} al ${DateFormat('dd/MM/yyyy').format(_fechaFin!)}', 
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Pedido', 'Cliente', 'Productos', 'Total', 'Fecha'],
              data: pedidos.map((p) => [
                p['numero_pedido']?.toString() ?? '',
                p['cliente']?.toString() ?? '',
                p['productos_json']?.toString() ?? '',
                'L ${(p['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                p['fecha']?.toString() ?? '',
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
              cellStyle: const pw.TextStyle(fontSize: 10),
            ),
          ];
        },
      ),
    );
    String nombre = 'Reporte_General_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await _guardarYCompartirPdf(pdf, nombre);
  }

  Future<void> _generarPdfProductosVendidos() async {
    final pdf = pw.Document();
    final db = await DatabaseHelper.instance.database;
    final pedidos = await db.query('pedidos');
    Map<String, int> conteoProductos = {};
    for (var pedido in pedidos) {
      String productosJson = pedido['productos_json']?.toString() ?? '';
      List<String> items = productosJson.split(';');
      for (var item in items) {
        item = item.trim();
        if (item.isEmpty) continue;
        RegExp regExp = RegExp(r'\s*\(x(\d+)\)$');
        Match? match = regExp.firstMatch(item);
        int cantidad = 1;
        String nombreProd = item;
        if (match != null) {
          cantidad = int.tryParse(match.group(1) ?? '1') ?? 1;
          nombreProd = item.replaceFirst(regExp, '').trim();
          
          int bracketIdx = nombreProd.indexOf(' [');
          if (bracketIdx != -1) {
            nombreProd = nombreProd.substring(0, bracketIdx).trim();
          }
        }
        conteoProductos[nombreProd] = (conteoProductos[nombreProd] ?? 0) + cantidad;
      }
    }
    final listaOrdenada = conteoProductos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Reporte de Productos Vendidos', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 15),
              pw.Table.fromTextArray(
                headers: ['Producto', 'Cantidad Total Vendida'],
                data: listaOrdenada.map((e) => [e.key, e.value.toString()]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
              ),
            ],
          );
        },
      ),
    );
    String nombre = 'Reporte_Productos_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await _guardarYCompartirPdf(pdf, nombre);
  }

  Future<void> _generarPdfRangoPedidos() async {
    if (_idPedidoInicio == null || _idPedidoFin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona el pedido inicial y final')),
      );
      return;
    }
    if (_idPedidoInicio! > _idPedidoFin!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El pedido inicial no puede ser mayor que el final')),
      );
      return;
    }
    final db = await DatabaseHelper.instance.database;
    final pedidos = await db.query(
      'pedidos',
      where: 'id BETWEEN ? AND ?',
      whereArgs: [_idPedidoInicio, _idPedidoFin],
      orderBy: 'id ASC',
    );
    if (pedidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontraron pedidos en ese rango')),
      );
      return;
    }
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        build: (pw.Context context) {
          return [
            pw.Text('Reporte por Rango de Pedidos', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 15),
            pw.Table.fromTextArray(
              headers: ['Pedido', 'Cliente', 'Productos', 'Total', 'Fecha'],
              data: pedidos.map((p) => [
                p['numero_pedido']?.toString() ?? '',
                p['cliente']?.toString() ?? '',
                p['productos_json']?.toString() ?? '',
                'L ${(p['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                p['fecha']?.toString() ?? '',
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
              cellStyle: const pw.TextStyle(fontSize: 10),
            ),
          ];
        },
      ),
    );
    String nombre = 'Rango_Pedidos_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await _guardarYCompartirPdf(pdf, nombre);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar PDF'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reporte General de Ventas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 5),
                    const Text('Filtra por fechas o déjalas vacías para exportar todo.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(_fechaInicio == null ? 'Fecha Inicio' : DateFormat('dd/MM/yyyy').format(_fechaInicio!)),
                            onPressed: () async {
                              DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) setState(() => _fechaInicio = picked);
                            },
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(_fechaFin == null ? 'Fecha Fin' : DateFormat('dd/MM/yyyy').format(_fechaFin!)),
                            onPressed: () async {
                              DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) setState(() => _fechaFin = picked);
                            },
                          ),
                        ),
                        if (_fechaInicio != null || _fechaFin != null)
                          IconButton(
                            icon: const Icon(Icons.clear, color: Colors.red, size: 18),
                            tooltip: 'Limpiar fechas',
                            onPressed: () => setState(() {
                              _fechaInicio = null;
                              _fechaFin = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                        onPressed: _generarPdfGeneral,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Exportar General'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            Card(
              elevation: 3,
              child: ListTile(
                leading: const Icon(Icons.bar_chart, color: Colors.indigo, size: 36),
                title: const Text('Reporte por Productos Vendidos', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Exporta el total acumulado de unidades vendidas por cada producto.'),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: _generarPdfProductosVendidos,
                  child: const Text('Exportar'),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reporte por Rango de Pedidos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 5),
                    const Text('Selecciona el pedido inicial y final para agruparlos en un PDF.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 10),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: DatabaseHelper.instance.database.then((db) => db.query('pedidos', orderBy: 'id ASC')),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final pedidos = snapshot.data!;
                        if (pedidos.isEmpty) {
                          return const Text('No hay pedidos disponibles.', style: TextStyle(color: Colors.red, fontSize: 12));
                        }
                        return Column(
                          children: [
                            DropdownButtonFormField<int>(
                              decoration: const InputDecoration(
                                labelText: 'Pedido Inicial',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              ),
                              value: _idPedidoInicio,
                              items: pedidos.map((p) {
                                return DropdownMenuItem<int>(
                                  value: p['id'] as int,
                                  child: Text('${p['numero_pedido']} - ${p['cliente']}', overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _idPedidoInicio = val),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                              decoration: const InputDecoration(
                                labelText: 'Pedido Individual / Fin',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              ),
                              value: _idPedidoFin,
                              items: pedidos.map((p) {
                                return DropdownMenuItem<int>(
                                  value: p['id'] as int,
                                  child: Text('${p['numero_pedido']} - ${p['cliente']}', overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _idPedidoFin = val),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                        onPressed: _generarPdfRangoPedidos,
                        child: const Text('Exportar Rango de Pedidos'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
