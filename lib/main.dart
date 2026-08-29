import 'package:flutter/material.dart';
import 'google_sheets_service.dart';

void main() {
  runApp(const MiAppVentas());
}

class MiAppVentas extends StatelessWidget {
  const MiAppVentas({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'App Ventas ExportPdf',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: false,
      ),
      home: const PantallaPrincipal(),
    );
  }
}

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class ItemVenta {
  final Producto producto;
  int cantidad;
  double get total => producto.precio * cantidad;

  ItemVenta({required this.producto, required this.cantidad});
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  int _indicePestana = 0;
  List<Cliente> clientes = [];
  List<Producto> productos = [];
  bool cargando = false;

  // Variables para la pestaña "Crear Venta"
  Cliente? clienteSeleccionado;
  Producto? productoSeleccionado;
  final TextEditingController txtCantidad = TextEditingController(text: '1');
  List<ItemVenta> detalleVenta = [];

  @override
  void initState() {
    super.initState();
    cargarDatosDesdeSheets();
  }

  Future<void> cargarDatosDesdeSheets() async {
    setState(() => cargando = true);
    
    try {
      final listaClientes = await GoogleSheetsService.obtenerClientes();
      final listaProductos = await GoogleSheetsService.obtenerProductos();

      if (mounted) {
        setState(() {
          clientes = listaClientes;
          productos = listaProductos;
          cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => cargando = false);
      }
    }
  }

  void _agregarProductoAVenta() {
    if (productoSeleccionado == null) return;
    int cant = int.tryParse(txtCantidad.text) ?? 1;
    if (cant <= 0) return;

    setState(() {
      final index = detalleVenta.indexWhere((item) => item.producto.codigo == productoSeleccionado!.codigo);
      if (index >= 0) {
        detalleVenta[index].cantidad += cant;
      } else {
        detalleVenta.add(ItemVenta(producto: productoSeleccionado!, cantidad: cant));
      }
      productoSeleccionado = null;
      txtCantidad.text = '1';
    });
  }

  double get totalVenta => detalleVenta.fold(0, (sum, item) => sum + item.total);

  // --- OPCIONES PARA CLIENTES (EDITAR / ELIMINAR) ---
  void _mostrarDialogoEditarCliente(Cliente c) {
    final txtNombre = TextEditingController(text: c.nombre);
    final txtTelefono = TextEditingController(text: c.telefono);
    final txtDireccion = TextEditingController(text: c.direccion);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar Cliente (${c.codigo})'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: txtNombre, decoration: const InputDecoration(labelText: 'Nombre')),
              TextField(controller: txtTelefono, decoration: const InputDecoration(labelText: 'Teléfono')),
              TextField(controller: txtDireccion, decoration: const InputDecoration(labelText: 'Dirección')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              c.nombre = txtNombre.text;
              c.telefono = txtTelefono.text;
              c.direccion = txtDireccion.text;
              setState(() => cargando = true);
              await GoogleSheetsService.editarCliente(c);
              await cargarDatosDesdeSheets();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _confirmarEliminarCliente(Cliente c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: Text('¿Deseas eliminar a ${c.nombre}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => cargando = true);
              await GoogleSheetsService.eliminarCliente(c.codigo);
              await cargarDatosDesdeSheets();
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // --- OPCIONES PARA PRODUCTOS (EDITAR / ELIMINAR) ---
  void _mostrarDialogoEditarProducto(Producto p) {
    final txtNombre = TextEditingController(text: p.nombre);
    final txtPrecio = TextEditingController(text: p.precio.toString());
    final txtStock = TextEditingController(text: p.stock.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar Producto (${p.codigo})'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: txtNombre, decoration: const InputDecoration(labelText: 'Nombre')),
              TextField(controller: txtPrecio, decoration: const InputDecoration(labelText: 'Precio'), keyboardType: TextInputType.number),
              TextField(controller: txtStock, decoration: const InputDecoration(labelText: 'Stock'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              p.nombre = txtNombre.text;
              p.precio = double.tryParse(txtPrecio.text) ?? p.precio;
              p.stock = int.tryParse(txtStock.text) ?? p.stock;
              setState(() => cargando = true);
              await GoogleSheetsService.editarProducto(p);
              await cargarDatosDesdeSheets();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _confirmarEliminarProducto(Producto p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content: Text('¿Deseas eliminar el producto ${p.nombre}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => cargando = true);
              await GoogleSheetsService.eliminarProducto(p.codigo);
              await cargarDatosDesdeSheets();
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> paginas = [
      // PESTAÑA 0: CREAR VENTA (CON BUSCADORES DE CLIENTES Y PRODUCTOS)
      cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Buscar / Seleccionar Cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Cliente>(
                    value: clienteSeleccionado,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                      hintText: 'Seleccione un cliente',
                    ),
                    isExpanded: true,
                    items: clientes.map((c) {
                      return DropdownMenuItem<Cliente>(
                        value: c,
                        child: Text('${c.nombre} (${c.codigo})'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => clienteSeleccionado = val),
                  ),
                  const SizedBox(height: 20),
                  const Text('Buscar / Seleccionar Producto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<Producto>(
                          value: productoSeleccionado,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.shopping_bag),
                            hintText: 'Seleccione un producto',
                          ),
                          isExpanded: true,
                          items: productos.map((p) {
                            return DropdownMenuItem<Producto>(
                              value: p,
                              child: Text('${p.nombre} - L ${p.precio.toStringAsFixed(2)}'),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => productoSeleccionado = val),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: txtCantidad,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Cant.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('AGREGAR A LA VENTA'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: _agregarProductoAVenta,
                    ),
                  ),
                  const Divider(height: 30, thickness: 2),
                  const Text('Detalle de la Venta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  detalleVenta.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No hay productos agregados')))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: detalleVenta.length,
                          itemBuilder: (ctx, i) {
                            final item = detalleVenta[i];
                            return Card(
                              child: ListTile(
                                title: Text(item.producto.nombre),
                                subtitle: Text('${item.cantidad} x L ${item.producto.precio.toStringAsFixed(2)} = L ${item.total.toStringAsFixed(2)}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      detalleVenta.removeAt(i);
                                    });
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('L ${totalVenta.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ],
              ),
            ),

      const Center(child: Text('Pantalla Historial')),

      // PESTAÑA CLIENTES CON ICONOS DE EDITAR Y ELIMINAR
      cargando
          ? const Center(child: CircularProgressIndicator())
          : clientes.isEmpty
              ? const Center(child: Text('No hay clientes registrados'))
              : ListView.builder(
                  itemCount: clientes.length,
                  itemBuilder: (context, i) {
                    final c = clientes[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text(c.codigo)),
                      title: Text(c.nombre),
                      subtitle: Text('Teléfono: ${c.telefono}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _mostrarDialogoEditarCliente(c),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _confirmarEliminarCliente(c),
                          ),
                        ],
                      ),
                    );
                  },
                ),

      // PESTAÑA PRODUCTOS CON ICONOS DE EDITAR Y ELIMINAR
      cargando
          ? const Center(child: CircularProgressIndicator())
          : productos.isEmpty
              ? const Center(child: Text('No hay productos registrados'))
              : ListView.builder(
                  itemCount: productos.length,
                  itemBuilder: (context, i) {
                    final p = productos[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text(p.codigo)),
                      title: Text(p.nombre),
                      subtitle: Text('L ${p.precio.toStringAsFixed(2)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _mostrarDialogoEditarProducto(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _confirmarEliminarProducto(p),
                          ),
                        ],
                      ),
                    );
                  },
                ),

      const Center(child: Text('Pantalla Resumen')),
      const Center(child: Text('Pantalla Productos Barcode')),
      const Center(child: Text('Pantalla PDF')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Ventas ExportPdf'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: cargarDatosDesdeSheets,
          )
        ],
      ),
      body: paginas[_indicePestana],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indicePestana,
        onTap: (index) => setState(() => _indicePestana = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Crear'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historial'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Clientes'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Productos'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Resumen'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Prod...'),
          BottomNavigationBarItem(icon: Icon(Icons.picture_as_pdf), label: 'PDF'),
        ],
      ),
    );
  }
}