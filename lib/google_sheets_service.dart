import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import '../models/cliente.dart';
import '../models/producto.dart';
import '../models/pedido.dart';

class GoogleSheetsService {
  // Enlaces CSV para lectura directa ultrarrápida
  static const String _urlClientesCsv = 
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vTmtKhEE5ziDtm_BQdAeOy8c-Z6H6_GbyKcPOvtdjfKtXgxYObBUB-PlK0ldsiwrW78aabDzei-R2Cd/pub?gid=0&single=true&output=csv';
  
  static const String _urlProductosCsv = 
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vTmtKhEE5ziDtm_BQdAeOy8c-Z6H6_GbyKcPOvtdjfKtXgxYObBUB-PlK0ldsiwrW78aabDzei-R2Cd/pub?gid=1903712481&single=true&output=csv';

  // Enlace Web App para guardar pedidos
  static const String _urlScriptExec = 
      'https://script.google.com/macros/s/AKfycbyiT2h9i6JyJvfHHk72xEtCEzHNdst5uHtMKfRJH_oXqZqloqiiX-jFmY3fA96JuoY9/exec';

  // Obtener Clientes desde CSV público
  Future<List<Cliente>> getClientes() async {
    try {
      final response = await http.get(Uri.parse(_urlClientesCsv));
      if (response.statusCode == 200) {
        List<List<dynamic>> csvData = const CsvToListConverter().convert(response.body);
        List<Cliente> clientes = [];
        
        // Omitimos la primera fila (cabecera)
        for (var i = 1; i < csvData.length; i++) {
          var row = csvData[i];
          if (row.isNotEmpty && row[0].toString().trim().isNotEmpty) {
            clientes.add(Cliente.fromCsvRow(row));
          }
        }
        return clientes;
      } else {
        throw Exception('Error al cargar clientes: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en getClientes: $e');
      return [];
    }
  }

  // Obtener Productos desde CSV público
  Future<List<Producto>> getProductos() async {
    try {
      final response = await http.get(Uri.parse(_urlProductosCsv));
      if (response.statusCode == 200) {
        List<List<dynamic>> csvData = const CsvToListConverter().convert(response.body);
        List<Producto> productos = [];
        
        // Omitimos la primera fila (cabecera)
        for (var i = 1; i < csvData.length; i++) {
          var row = csvData[i];
          if (row.isNotEmpty && row[0].toString().trim().isNotEmpty) {
            productos.add(Producto.fromCsvRow(row));
          }
        }
        return productos;
      } else {
        throw Exception('Error al cargar productos: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en getProductos: $e');
      return [];
    }
  }

  // Guardar Pedido mediante el Web App /exec
  Future<bool> guardarPedido(Pedido pedido) async {
    try {
      final response = await http.post(
        Uri.parse(_urlScriptExec),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(pedido.toJson()),
      );

      return response.statusCode == 200 || response.statusCode == 302;
    } catch (e) {
      print('Error al guardar pedido: $e');
      return false;
    }
  }
}
