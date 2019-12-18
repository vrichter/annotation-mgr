#include "hungarian.hpp"
#include "luwra/lib/luwra.hpp"
#include <iostream>

using State = luwra::State;
using Table = luwra::Table;
using Matrix = Hungarian::Matrix;
using Cost = int;
using Row = std::vector<Cost>;
using Result = Hungarian::Result;

Matrix table_to_matrix(Table table) {
  Matrix matrix = Matrix();
  for (size_t i = 1;; ++i) {
    if (!table.has(i)) {
      break;
    }
    Table row_table = table.get<Table>(i);
    Row row;
    for (size_t j = 1;; ++j) {
      if (row_table.has(j)) {
        row.push_back(row_table.get<Cost>(j));
      } else {
        matrix.push_back(row);
        break;
      }
    }
  }
  return matrix;
}

Table matrix_to_table(Matrix &m, State *s) {
  Table main_table = Table(s);
  for (size_t i = 0; i < m.size(); ++i) {
    auto &row = m[i];
    Table row_table = Table(s);
    for (size_t j = 0; j < row.size(); ++j) {
      row_table.set(j + 1, row[j]);
    }
    main_table.set(i + 1, row_table);
  }
  return main_table;
}

Table matrix_to_assignment(Matrix &m, State *s) {
  Table table = Table(s);
  for (size_t i = 0; i < m.size(); ++i) {
    auto &row = m[i];
    for (size_t j = 0; j < row.size(); ++j) {
      if (row[j] == 1) {
        table.set(i + 1, j + 1);
        break;
      }
    }
  }
  return table;
}

Table create_result_table(Result result, State *s) {
  Table t(s);
  t["success"] = result.success;
  t["total_cost"] = result.totalCost;
  t["assignment"] = matrix_to_table(result.assignment, t.ref.life->state);
  t["assignment_map"] =
      matrix_to_assignment(result.assignment, t.ref.life->state);
  t["cost"] = matrix_to_table(result.cost, t.ref.life->state);
  return t;
}

Table optimize(Table table, Hungarian::MODE mode) {
  auto matrix = table_to_matrix(table);
  auto result = Hungarian::Solve(matrix, mode);
  auto result_table = create_result_table(result, table.ref.life->state);
  result_table["matrix"] = matrix_to_table(matrix, table.ref.life->state);
  return result_table;
}

Table maximize_utility(Table table) {
  return optimize(table, Hungarian::MODE_MAXIMIZE_UTIL);
}

Table minimize_cost(Table table) {
  return optimize(table, Hungarian::MODE_MINIMIZE_COST);
}

lua_CFunction fun_minimize_cost = LUWRA_WRAP(minimize_cost);
lua_CFunction fun_maximize_utility = LUWRA_WRAP(maximize_utility);

extern "C" {
int luaopen_munkres(lua_State *lua) {
  luwra::setGlobal(lua, "minimize_weights", fun_minimize_cost);
  luwra::setGlobal(lua, "maximize_utility", fun_maximize_utility);
  return 0;
}
}
